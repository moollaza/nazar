# Add a custom service

Users can monitor any supported status page that is not in the catalog by giving a name and an https URL. Nazar refuses non-https or host-less URLs before adding.

## Sub-features

- `custom-open` Settings > `Services` > `Add Custom...` opens the `Add Custom Service` sheet.
- `custom-reject-http` an `http://` URL shows `URL must be a valid https:// address with a host` and disables `Add`.
- `custom-accept` an https status page URL enables `Add`; adding it creates a row that polls.
- `custom-cancel` `Cancel` closes the sheet with nothing added.

## How to get to it (user POV)

- Settings > `Services` tab > `Add Custom...`.

## Driving it with nazar-app.sh

Preconditions:

- Baseline, then Settings open on the Services tab (through the gear, or `launch --fresh -- -UITestOpenSettingsAt Services` when the entry point is not under test).

- **Open.** Run `ax press "Add Custom..."`, `ax wait "Add Custom Service"`.
- **Reject http.** Run `ax click "Name (e.g. My Service)"`, `ax type "Example"`, `ax click "Status Page URL (e.g. https://status.example.com)"`, `ax type "http://status.example.com"`. `ax wait "URL must be a valid https:// address with a host"` passes and `ax find "Add"` shows `[disabled]`. `shot custom-reject`.
- **Accept https.** Replace the URL with a real page, for example `https://www.githubstatus.com`. The message disappears and `Add` is enabled. Press `Add`. `log "Added provider"` shows a line; the dashboard row for the name appears with a status within 20 s.
- **Cancel.** Reopen the sheet, type a name, press `Cancel`. The Services count is unchanged.

## Gotchas

- `status.example.com` is not a real status page. Use it only for validation; adding it yields `Unavailable`.
- The URL field has no clear button. Select all with a triple click (`ax click` three times) or reopen the sheet.
- A URL already in the list is refused silently in the UI; check the log for `Refused to add duplicate provider`.
