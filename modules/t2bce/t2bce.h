#ifndef APPLE_BCE_H
#define APPLE_BCE_H

#include <linux/pci.h>
#include <linux/spinlock.h>
#include <linux/mutex.h>
#include "mailbox.h"
#include "queue.h"
#include "vhci/vhci.h"

#define BC_PROTOCOL_VERSION 0x20001
#define BCE_MAX_QUEUE_COUNT 0x100

#define BCE_QUEUE_USER_MIN 2
#define BCE_QUEUE_USER_MAX (BCE_MAX_QUEUE_COUNT - 1)

struct t2bce_device {
    struct pci_dev *pci, *pci0;
    dev_t devt;
    struct device *dev;
    void __iomem *reg_mem_mb;
    void __iomem *reg_mem_dma;
    struct bce_mailbox mbox;
    struct bce_xhci_pm xhci_pm;
    struct bce_queue *queues[BCE_MAX_QUEUE_COUNT];
    struct spinlock queues_lock;
    struct ida queue_ida;
    struct bce_queue_cq *cmd_cq;
    struct bce_queue_cmdq *cmd_cmdq;
    struct bce_queue_sq *int_sq_list[BCE_MAX_QUEUE_COUNT];
    bool is_being_removed;

    dma_addr_t saved_data_dma_addr;
    void *saved_data_dma_ptr;
    size_t saved_data_dma_size;
    u32 fw_version;
    bool stateful_suspend_valid;
    bool no_state_fallback;
    bool mailbox_channel_active;
    struct mutex pm_lock;

    /* 2nd-suspend-per-boot fix (soft-teardown path):
     *  pm_stateful_restored - controller is currently in a stateful-restored
     *    state (a stateful save+restore happened and it has not been freshly
     *    re-probed since). A 2nd stateful save from this state is what wedges
     *    the T2 below Linux, so the next suspend tears down instead.
     *  pm_soft_torn_down - .prepare tore the controller down while awake; suspend
     *    must issue no SAVE_STATE_AND_SLEEP (0x17) and resume must rebuild. */
    bool pm_stateful_restored;
    bool pm_soft_torn_down;

    struct bce_vhci vhci;
    struct aaudio_device *aaudio;
};

extern struct t2bce_device *global_bce;

#endif //APPLE_BCE_H
