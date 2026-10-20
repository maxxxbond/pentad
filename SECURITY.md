# Security Policy

## Supported versions

Pentad is pre-1.0 and has no stable releases yet. Security fixes land on the `main` branch only. Once tagged releases exist, this section will name the supported ones.

## Reporting a vulnerability

Please do not open a public issue or pull request for a vulnerability.

Use GitHub's private vulnerability reporting: open the **Security** tab of the project repository and choose **Report a vulnerability**. If that option is not available, open a public issue that says only that you have a security report and asks for a private channel. Do not include details in it.

Include, as far as you can:

- what is affected (file, component, widget or tool) and the version or commit;
- the steps or a minimal proof of concept to reproduce it;
- the impact you expect: what an attacker gains and what they need first;
- your Quickshell, Qt and Hyprland versions.

The project is maintained by volunteers. Expect an acknowledgement within about a week, and a fix or a decision within about 90 days for valid reports. These are goals, not guarantees. Please keep the report private until a fix is available or 90 days have passed, whichever comes first. Reporters are credited in the release notes unless they prefer not to be.

## What is in scope

Pentad runs as your own user inside your Wayland session. It has no privilege separation, and it is not a sandbox. Reports are most useful when they show that something crosses a boundary the user did not choose to cross. Examples:

- command or script injection through data the shell does not own: notification text, window titles, media metadata, clipboard or dropped content, filenames, URLs, manifest or settings values;
- unsafe handling of the files the shell writes or reads: the shelf, screenshots, caches, the state directory, temporary files and symlinks;
- credentials ending up in configuration, logs or the network: for example API key files and `secret://` references;
- network requests that go to an unexpected destination or send more than the feature needs (weather, translation, lyrics, artwork, image search);
- escalation through the IPC and global-shortcut surface.

## What is out of scope

- **Widgets and plugins you install.** A widget is QML code that runs with your user's privileges, like any program you run. A malicious widget that you chose to install is not a vulnerability in Pentad. A bug that lets a widget exceed the permissions its manifest declares is in scope.
- A local attacker who already runs code as your user or controls your Quickshell, Hyprland or D-Bus session.
- Vulnerabilities in Quickshell, Qt, Hyprland or other dependencies. Report those to their projects. Tell us as well if Pentad's use of them makes the issue worse.
- Missing hardening, theoretical findings without an attack path, and denial of service by a user on their own session.

## Safe testing

Test only on systems you own, with private test sessions and throwaway data. Do not access other people's data, and do not run denial-of-service or social-engineering attacks. Good-faith research that follows this policy is welcome.
