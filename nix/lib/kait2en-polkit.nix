# Shared plumbing for the KaiT2en GUI apps that call a privileged helper via
# `pkexec /usr/local/libexec/<helper>` and ship a polkit `.policy` whose
# `org.freedesktop.policykit.exec.path` is that same absolute path.
#
# See PACKAGING-PLAN.md ("The one hard problem"): polkit only authorises when
# the path pkexec is invoked with is byte-for-byte equal to the policy's
# exec.path, so three things must agree — the constant baked into the app
# source, the exec.path in the installed policy, and the helper's on-disk
# location. On Fedora all three are /usr/local/libexec/<helper>; there is no
# such stable path on NixOS.
#
# The fix is to build each app as one derivation and point all three at that
# derivation's own $out/libexec/<helper>. `rewriteFhsPaths` does the
# substitution in one place: run it in postPatch against the source constants
# (before the Rust build, or against the installed .py for the Python apps) and
# again in postInstall against the installed .policy files. It also rewrites the
# hardcoded wordmark path to the branding store copy.
{ lib }:

rec {
  # The FHS locations upstream hardcodes.
  libexecDir = "/usr/local/libexec";
  wordmarkPath = "/usr/local/share/kait2en/kait2en-wordmark.png";

  # A bash snippet that rewrites, in each file of `files`, every
  # `${libexecDir}/<helper>` to `$out/libexec/<helper>` and the wordmark path to
  # the `branding` store copy. `--replace-quiet` so a file that lacks a given
  # constant is silently skipped (policies mention one helper, sources may
  # mention several). The replacement target uses a plain bash `$out`, which is
  # set for the whole build, so this works in postPatch as well as postInstall.
  #
  # `files` entries are shell-escaped, so an entry must be a literal path: for
  # source files use the relative path; for files already installed under the
  # output, use `builtins.placeholder "out"` (Nix substitutes it for the real
  # $out) rather than a bash `$out`, which the escaping would not expand.
  rewriteFhsPaths =
    {
      files,
      helpers,
      branding,
    }:
    let
      quotedFiles = lib.concatMapStringsSep " " lib.escapeShellArg files;
      helperReplacements = lib.concatMapStringsSep " " (
        h: ''--replace-quiet "${libexecDir}/${h}" "$out/libexec/${h}"''
      ) helpers;
    in
    ''
      for kait2enFile in ${quotedFiles}; do
        substituteInPlace "$kait2enFile" \
          ${helperReplacements} \
          --replace-quiet "${wordmarkPath}" "${branding}/share/kait2en/kait2en-wordmark.png"
      done
    '';
}
