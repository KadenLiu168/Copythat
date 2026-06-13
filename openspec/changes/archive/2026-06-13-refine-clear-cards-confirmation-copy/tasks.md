## 1. Confirmation Copy

- [x] 1.1 Update the clear-cards confirmation title to "Clear cards?"; verify the title is shorter and no behavior changes.
- [x] 1.2 Rename the default destructive action to "Clear Regular Cards"; verify it still calls the protected clear mode.
- [x] 1.3 Replace the message with "Regular cards exclude pinned cards and cards in pinboards."; verify the clear-all and cancel choices remain unchanged.

## 2. Verification And Archive

- [x] 2.1 Run `swift test`; verify existing settings and store tests pass.
- [x] 2.2 Run `./script/verify_all.sh`; verify full project checks pass.
- [x] 2.3 Sync the settings spec delta into the main settings spec and archive the completed change.
