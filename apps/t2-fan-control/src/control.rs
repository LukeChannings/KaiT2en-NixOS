use std::{
    collections::VecDeque,
    time::{Duration, Instant},
};

use crate::{
    config::{curve_for_preset, AppConfig, CurvePoint},
    error::Result,
    sysfs::{FanEndpoint, TemperatureSnapshot, TemperatureSource},
};

/// Number of recent temperature samples the controller tracks (~800ms apart,
/// so this is roughly a 6-7s window). The control temperature is the PEAK of
/// this window, not the mean: fans must lead temperature, and on a chip that
/// can jump 50->100C in seconds a long mean-smoothed window left the fans
/// trailing far behind the spike and the package riding Tjmax. A short
/// peak-hold window reacts immediately to a spike and decays within seconds
/// once it passes.
const SAMPLE_WINDOW: usize = 8;

pub struct Controller {
    samples: VecDeque<u8>,
    last_applied_percent: Option<u8>,
    last_tick: Instant,
}

#[derive(Clone, Debug, Default)]
pub struct ControlSnapshot {
    pub temperatures: TemperatureSnapshot,
    pub effective_temp_c: Option<u8>,
    pub target_percent: Option<u8>,
    pub target_rpm_per_fan: Vec<u32>,
}

impl Controller {
    pub fn new() -> Self {
        Self {
            samples: VecDeque::with_capacity(SAMPLE_WINDOW),
            last_applied_percent: None,
            last_tick: Instant::now() - Duration::from_secs(5),
        }
    }

    pub fn tick(
        &mut self,
        config: &AppConfig,
        fans: &mut [FanEndpoint],
        temperatures: &mut [TemperatureSource],
    ) -> Result<ControlSnapshot> {
        let snapshot = TemperatureSnapshot::read_from(temperatures);
        let effective_temp = snapshot.effective_temp_c();

        if let Some(temp) = effective_temp {
            self.samples.push_back(temp);
            if self.samples.len() > SAMPLE_WINDOW {
                self.samples.pop_front();
            }
        }

        let smoothed_temp = self.smoothed_temp();
        let curve = curve_for_preset(config);
        let target_percent = smoothed_temp.map(|temp| interpolate_percent(&curve, temp));

        let mut target_rpm_per_fan = Vec::with_capacity(fans.len());
        if config.automatic_control_enabled {
            let should_apply = should_apply_target(self.last_applied_percent, target_percent);

            for fan in fans {
                // Failsafe: a missing target means we have no usable temperature
                // reading (sensor read failed / not yet sampled). Once we have
                // taken the fans out of SMC auto we own cooling, so an unknown
                // temperature must drive them to MAX, never min — running a
                // sensorless fan at minimum is how the package reaches Tjmax and
                // the platform force-suspends.
                let rpm = target_percent
                    .map(|percent| fan.percent_to_rpm(percent))
                    .unwrap_or(fan.max_speed);

                if should_apply {
                    fan.set_target_speed(rpm)?;
                    fan.current_speed = Some(rpm);
                    fan.app_controlled = Some(true);
                }

                target_rpm_per_fan.push(rpm);
            }

            if should_apply {
                self.last_applied_percent = target_percent;
            }
        }

        self.last_tick = Instant::now();

        Ok(ControlSnapshot {
            temperatures: snapshot,
            effective_temp_c: smoothed_temp,
            target_percent,
            target_rpm_per_fan,
        })
    }

    pub fn release_to_system(&mut self, fans: &mut [FanEndpoint]) -> Result<()> {
        for fan in fans {
            fan.release_to_auto()?;
            fan.app_controlled = Some(false);
        }
        self.last_applied_percent = None;
        Ok(())
    }

    pub fn should_tick(&self) -> bool {
        self.last_tick.elapsed() >= Duration::from_millis(800)
    }

    fn smoothed_temp(&self) -> Option<u8> {
        // Peak-hold over the recent window (see SAMPLE_WINDOW): track the hottest
        // recent reading so the fans lead a temperature spike instead of
        // trailing a slow mean. The peak ages out of the window within a few
        // seconds once load drops, so the fans still wind back down.
        self.samples.iter().copied().max()
    }
}

fn should_apply_target(last_applied_percent: Option<u8>, next_target_percent: Option<u8>) -> bool {
    match (last_applied_percent, next_target_percent) {
        (None, Some(_)) | (Some(_), None) => true,
        (None, None) => false,
        (Some(previous), Some(next)) => previous.abs_diff(next) >= 3,
    }
}

fn interpolate_percent(curve: &[CurvePoint], temp_c: u8) -> u8 {
    if curve.is_empty() {
        return 0;
    }
    if temp_c <= curve[0].temp_c {
        return curve[0].speed_percent;
    }
    for window in curve.windows(2) {
        let left = &window[0];
        let right = &window[1];
        if temp_c <= right.temp_c {
            let temp_span = (right.temp_c - left.temp_c) as f32;
            if temp_span <= f32::EPSILON {
                return right.speed_percent;
            }
            let progress = (temp_c - left.temp_c) as f32 / temp_span;
            let speed_span = right.speed_percent as f32 - left.speed_percent as f32;
            return (left.speed_percent as f32 + progress * speed_span).round() as u8;
        }
    }
    curve.last().map(|point| point.speed_percent).unwrap_or(100)
}
