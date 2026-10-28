// pm2 process file for the MyTime desktop pet.
// Build first: ./MyTime/build.sh, then: pm2 start ecosystem.config.js
module.exports = {
  apps: [
    {
      name: 'mytime',
      script: './MyTime/build/MyTime.app/Contents/MacOS/MyTime',
      cwd: __dirname,
      interpreter: 'none',
      autorestart: true,
      // "Quit" from the gear menu exits with 0 — respect it instead of respawning.
      stop_exit_codes: [0],
      max_restarts: 5,
      restart_delay: 2000,
    },
  ],
};
