# Herdr for Intel Mac

Unofficial builds of [Herdr](https://github.com/herdrdev/herdr-app) (Apache-2.0) for Intel Macs running **macOS 13 or newer**, compiled from the official source on GitHub's Intel macOS runners. Not affiliated with the Herdr project.

## How it works

- `.github/workflows/build.yml` runs every 6 hours. It reads the version Herdr has released (`releases.herdr.dev/app/latest.json`). If this repo has no release for that version yet, it builds the matching upstream tag. It uses upstream's own Rust and Zig versions and `MACOSX_DEPLOYMENT_TARGET=13.0`, then publishes `herdr-app-macos-x86_64.tar.gz` and `SHA256SUMS` as a GitHub Release.
- `update-herdr.sh` installs or updates the app on your Mac from the latest release, then runs `hc update` to update herdr-core from the official server.

Builds don't set `HERDR_APP_RELEASE`, so the app never tries to pull the official Apple Silicon updates and sends no release telemetry. The app is ad hoc signed, not notarized. It's downloaded with curl, so macOS doesn't quarantine it.

## Setup

1. Create a **public** GitHub repo, e.g. `herdr-intel-mac`, and push this folder to it. Public repos get macOS runner minutes free.
2. In the repo, go to **Settings → Actions → General → Workflow permissions** and choose **Read and write permissions**.
3. Go to **Actions → Build Herdr for Intel Mac → Run workflow**. The first build takes the longest; later ones reuse the cache.
4. On your Mac, set `REPO` at the top of `update-herdr.sh` to `your-user/herdr-intel-mac`, then run:

   ```sh
   ./update-herdr.sh            # install now
   ./update-herdr.sh schedule   # check daily at 10:00 and at login
   ```

   Quit and reopen Herdr after an update (your terminals keep running in the core).

To rebuild a version, run the workflow with **force**. To build a specific version, enter it in **version**.

## Notes

- GitHub switches off schedules in repos with no activity for 60 days. The workflow commits `LATEST` on every release to prevent that. If it ever gets switched off, re-enable it on the Actions tab.
- `macos-15-intel` is GitHub's last Intel runner image. When GitHub retires it, this workflow stops working.
