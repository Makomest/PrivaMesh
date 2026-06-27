# App Store screenshots

Telegram-style panels (1290x2796, 6.7") generated from raw app screenshots.

## How to make them
1. Run the app in the **iPhone 16 Plus** simulator (6.7"), Dark theme.
2. Capture each screen with **Cmd+S** (saves a 1290x2796 PNG).
3. Drop them into `raw/` named `1.png` ... `6.png` in this order:
   1. Chat (E2E)            -> "Private by default"
   2. No-servers onboarding -> "No servers. Seriously."
   3. Chat info panel       -> "Hide who, when, how"
   4. Add contact / search  -> "No phone. No email."
   5. Wallet                -> "Send value in chat"
   6. Market / NFT avatars  -> "Own your identity"
4. Run: `python3 generate.py`  (needs Pillow: `pip3 install --user pillow`)
5. Upload `out/1.png ... out/6.png` to App Store Connect.

Edit headlines/colors in `PANELS` inside `generate.py`. Missing raw files render a placeholder.
