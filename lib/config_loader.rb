# frozen_string_literal: true

require 'yaml'

class ConfigLoader
  CONFIG_PATH = File.expand_path('../../config/config.yml', __FILE__)

  def self.load
    unless File.exist?(CONFIG_PATH)
      raise "Configuration file not found at #{CONFIG_PATH}. " \
            "Please copy config/config.yml.example to config/config.yml and fill in your credentials."
    end

    config = YAML.load_file(CONFIG_PATH)
    validate!(config)
    config
  end

  def self.validate!(config)
    errors = []

    # Validate Jira config
    jira = config['jira'] || {}
    errors << 'jira.base_url is required' if jira['base_url'].to_s.empty?
    errors << 'jira.email is required' if jira['email'].to_s.empty?
    errors << 'jira.api_token is required' if jira['api_token'].to_s.empty?

    # Validate Slack config
    slack = config['slack'] || {}
    errors << 'slack.bot_token is required' if slack['bot_token'].to_s.empty?

    # Validate teams
    teams = config['teams'] || {}
    errors << 'At least one team must be configured' if teams.empty?

    raise "Configuration errors:\n#{errors.map { |e| "  - #{e}" }.join("\n")}" unless errors.empty?
  end
end
