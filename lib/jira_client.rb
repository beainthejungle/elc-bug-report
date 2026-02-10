# frozen_string_literal: true

require 'faraday'
require 'json'
require 'base64'

class JiraClient
  MAX_RESULTS = 100
  # The squad field name for JQL queries vs the customfield ID for reading values
  SQUAD_FIELD_ID = 'customfield_10041'

  def initialize(config)
    @config = config
    @base_url = config['base_url']
    @email = config['email']
    @api_token = config['api_token']
    @squad_field = config['squad_field'] || 'squad[Dropdown]'
  end

  def fetch_all_issues(squads, statuses)
    jql = build_jql(squads, statuses)
    puts "JQL: #{jql}"

    all_issues = []
    next_page_token = nil

    loop do
      puts "Fetching issues#{next_page_token ? ' (next page)' : ''}..."

      body = {
        jql: jql,
        maxResults: MAX_RESULTS,
        fields: ['summary', 'status', 'priority', 'assignee', 'issuetype', SQUAD_FIELD_ID]
      }
      body[:nextPageToken] = next_page_token if next_page_token

      response = connection.post('/rest/api/3/search/jql') do |req|
        req.body = body.to_json
      end

      unless response.success?
        puts "Jira API error: #{response.status} - #{response.body}"
        break
      end

      data = JSON.parse(response.body)
      issues = data['issues'] || []
      puts "Got #{issues.length} issues"

      all_issues.concat(issues)

      next_page_token = data['nextPageToken']
      break if next_page_token.nil? || issues.empty?
    end

    puts "Total issues fetched: #{all_issues.length}"
    all_issues.map { |issue| normalize_issue(issue) }
  end

  private

  def build_jql(squads, statuses)
    squad_values = squads.map { |s| "\"#{s}\"" }.join(', ')
    all_statuses = (statuses['active'] + statuses['blocked']).map { |s| "\"#{s}\"" }.join(', ')

    'project = FCT AND ' \
    'issuetype IN (Bug, Chore) AND ' \
    "\"#{@squad_field}\" IN (#{squad_values}) AND " \
    "status IN (#{all_statuses}) " \
    'ORDER BY priority ASC, created ASC'
  end

  def normalize_issue(issue)
    fields = issue['fields'] || {}
    squad_value = fields[SQUAD_FIELD_ID]

    # Handle different squad field formats
    squad = if squad_value.is_a?(Hash)
              squad_value['value']
            elsif squad_value.is_a?(Array) && squad_value.first.is_a?(Hash)
              squad_value.first['value']
            else
              squad_value
            end

    {
      key: issue['key'],
      summary: fields['summary'],
      priority: fields.dig('priority', 'name'),
      assignee: fields.dig('assignee', 'displayName'),
      status: fields.dig('status', 'name'),
      issue_type: fields.dig('issuetype', 'name'),
      squad: squad
    }
  end

  def connection
    @connection ||= Faraday.new(url: @base_url) do |f|
      f.request :authorization, :basic, @email, @api_token
      f.headers['Content-Type'] = 'application/json'
      f.headers['Accept'] = 'application/json'
      f.adapter Faraday.default_adapter
    end
  end
end
