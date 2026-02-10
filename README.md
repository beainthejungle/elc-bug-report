# ELC Bug Report Tool

A CLI tool that fetches bug and chore data from Jira for the Employee Lifecycle (ELC) domain and posts a formatted summary to Slack.

## Squads

This tool tracks bugs for the following ELC squads:
- **Organizations** - Team managing organization structures
- **Contracts** - Team handling employee contracts
- **OffOnBoarding** - Team managing employee onboarding and offboarding

## Prerequisites

- Ruby 3.3.5 (see `.tool-versions`)
- Bundler
- Jira API access
- Slack Bot token

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/beainthejungle/elc-bug-report.git
   cd elc-bug-report
   ```

2. Install dependencies:
   ```bash
   bundle install
   ```

3. Create your configuration file:
   ```bash
   cp config/config.yml.example config/config.yml
   ```

4. Edit `config/config.yml` with your credentials:
   - Add your Jira email and API token
   - Add your Slack bot token
   - Adjust the Slack channel if needed

## Configuration

The `config/config.yml` file contains:

```yaml
jira:
  base_url: https://factorial-hr.atlassian.net
  email: your-email@factorial.co
  api_token: your-jira-api-token
  squad_field: customfield_10041

slack:
  bot_token: xoxb-your-slack-bot-token
  default_channel: "#employee-lifecycle-teams"

teams:
  Contracts:
    - "Contracts"
  OffOnBoarding:
    - "OffOnBoarding"
  Organizations:
    - "Organizations"
```

## Slack Bot Setup

1. Go to [Slack API Apps](https://api.slack.com/apps)
2. Create a new app or use an existing one
3. Add the following Bot Token Scopes under OAuth & Permissions:
   - `chat:write` - To post messages
   - `chat:write.public` - To post to public channels without joining
4. Install the app to your workspace
5. Copy the Bot User OAuth Token (starts with `xoxb-`)
6. Invite the bot to your channel: `/invite @YourBotName`

## Usage

### Dry Run (test without posting to Slack)

```bash
./bin/elc_bug_report --dry-run
```

### Post to Slack

```bash
./bin/elc_bug_report
```

### Specify a different channel

```bash
./bin/elc_bug_report --channel "#elc-bugs-test"
```

## Output Example

The report includes:
- Total bugs and chores count
- Breakdown by squad with icons:
  - :office: Organizations
  - :memo: Contracts
  - :rocket: OffOnBoarding
- Fun facts about the numbers
- Links to Jira filters for each category

## Development

The tool is structured as follows:

```
.
├── bin/
│   └── elc_bug_report      # CLI executable
├── config/
│   ├── config.yml          # Your config (gitignored)
│   ├── config.yml.example  # Example config
│   └── fun_facts.yml       # Fun facts for numbers
└── lib/
    ├── config_loader.rb    # Configuration loading
    ├── fun_facts.rb        # Fun facts logic
    ├── jira_client.rb      # Jira API client
    ├── report_builder.rb   # Report formatting
    └── slack_client.rb     # Slack API client
```

## Credits

Based on [jira-slack-bugs-report](https://github.com/danigonza/jira-slack-bugs-report) by the Finance team.
