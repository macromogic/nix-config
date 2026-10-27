
## This machine
- My own desktop: WSL2 (Ubuntu) on Windows, not a shared server. sudo
  needs my password, so when a step needs root, give me the command to
  run instead of trying it.
- CUDA, conda (~/miniconda3) and rustup are installed outside Nix and
  managed by hand. Don't modify, reinstall or reconfigure them; ask first.
- The Windows drives are mounted under /mnt (for example /mnt/c). Don't
  write there unless I ask.
