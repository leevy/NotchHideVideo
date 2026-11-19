# NotchHideVideo
A simplistic tool to hide the notch on MacOS.

One thing bothers me about my new Mac Book is the "notch". Visually, it's really bad and I tried to find a way to hide it.

First, I tried the ["NotchHide"](https://github.com/drtaru/NotchHide). It's quite good, however, it doesn't support dynamic video wallpaper. 

So, I vibe-coded my own version and added this feature. It turned out pretty good.

Download the app: [release]()

---

### How to Compile and Run on Your Mac

1. Make sure Apple's Command Line Tools are installed (skip if already installed):
   ```bash
   xcode-select --install
   ```
2. Inside the `NotchHideVideo` folder containing the files above, run:
   ```bash
   chmod +x build.sh
   ./build.sh
   open build/NotchHideVideo.app
   ```
3. To keep it installed permanently (and enable **Launch at Login**), drag `build/NotchHideVideo.app` into `/Applications`.
4. **Recommended usage note:** Make sure **System Settings > Menu Bar > Show menu bar background** is turned **off** so macOS doesn't layer a gray glass bar over the black strip. For dark dynamic video wallpapers, **Live Overlay Mode** works immediately with zero CPU/disk overhead; if you switch to a bright daytime dynamic video where macOS turns the menu text black, click the menu bar icon and use either **Apply Patched Still Frame** (instant) or **Bake Black Bar Into Dynamic Video (.mov)** (takes a minute or two on 4K 240fps Aerials).
