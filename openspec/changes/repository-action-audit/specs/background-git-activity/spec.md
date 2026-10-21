# Spec Delta

## MODIFIED Requirements

### Requirement: Repository name opens the activity popover
Clicking the repository-name component SHALL open a popover with two tabs, Audit and Background. The Background tab SHALL list the window's running, queued, and failed background actions, each with a title (for example `Fetching remotes`). The popover SHALL open on the Background tab when background actions are running, queued, or failed, and on the Audit tab otherwise. The notification bell SHALL remain a separate control with its own behavior.

#### Scenario: Open popover
- **WHEN** the user clicks the repository name while a push is running
- **THEN** a popover opens on the Background tab and lists the push with a running state

#### Scenario: Empty popover
- **WHEN** the user switches to the Background tab with no background activity
- **THEN** the tab shows an empty state saying no background Git actions are running

#### Scenario: Idle popover opens on Audit
- **WHEN** the user clicks the repository name with no running, queued, or failed background actions
- **THEN** the popover opens on the Audit tab

#### Scenario: Bell is independent
- **WHEN** the user clicks the notification bell
- **THEN** the notification popover opens and the activity popover does not
