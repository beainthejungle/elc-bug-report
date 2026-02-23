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
    @project_key = config['project_key'] || 'FCT'
    @issue_types = config['issue_types'] || %w[Bug Chore]
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

  # Fetch the count of issues created last week
  def fetch_created_last_week_count(squads)
    jql = build_created_last_week_jql(squads)
    fetch_issue_count(jql, 'created last week')
  end

  # Fetch the count of issues resolved last week
  def fetch_solved_last_week_count(squads)
    jql = build_solved_last_week_jql(squads)
    fetch_issue_count(jql, 'solved last week')
  end

  # Fetch the sum of SLA points for all open issues
  def fetch_sla_points(squads, sla_field_name)
    jql = build_open_issues_jql(squads)
    puts "Fetching SLA points..."

    total_points = 0
    next_page_token = nil

    loop do
      body = {
        jql: jql,
        maxResults: MAX_RESULTS,
        fields: [sla_field_name]
      }
      body[:nextPageToken] = next_page_token if next_page_token

      response = connection.post('/rest/api/3/search/jql') do |req|
        req.body = body.to_json
      end

      unless response.success?
        puts "Jira API error fetching SLA: #{response.status} - #{response.body}"
        return nil
      end

      data = JSON.parse(response.body)
      issues = data['issues'] || []

      issues.each do |issue|
        points = issue.dig('fields', sla_field_name)
        total_points += points.to_f if points
      end

      next_page_token = data['nextPageToken']
      break if next_page_token.nil? || issues.empty?
    end

    puts "Total SLA points: #{total_points}"
    total_points
  end

  private

  def issue_types_jql
    @issue_types.map { |t| "\"#{t}\"" }.join(', ')
  end

  def squad_jql(squads)
    squad_values = squads.map { |s| "\"#{s}\"" }.join(', ')
    "\"#{@squad_field}\" IN (#{squad_values})"
  end

  def build_jql(squads, statuses)
    all_statuses = (statuses['active'] + statuses['blocked']).map { |s| "\"#{s}\"" }.join(', ')

    "project = #{@project_key} AND " \
    "issuetype IN (#{issue_types_jql}) AND " \
    "#{squad_jql(squads)} AND " \
    "status IN (#{all_statuses}) " \
    'ORDER BY priority ASC, created ASC'
  end

  def build_open_issues_jql(squads)
    "project = #{@project_key} AND " \
    "issuetype IN (#{issue_types_jql}) AND " \
    "#{squad_jql(squads)} AND " \
    'resolution = Unresolved'
  end

  def build_created_last_week_jql(squads)
    "project = #{@project_key} AND " \
    "issuetype IN (#{issue_types_jql}) AND " \
    "#{squad_jql(squads)} AND " \
    'created >= -1w'
  end

  def build_solved_last_week_jql(squads)
    "project = #{@project_key} AND " \
    "issuetype IN (#{issue_types_jql}) AND " \
    "#{squad_jql(squads)} AND " \
    'resolved >= -1w'
  end

  def fetch_issue_count(jql, label)
    puts "Fetching #{label}..."

    count = 0
    next_page_token = nil

    loop do
      body = {
        jql: jql,
        maxResults: MAX_RESULTS,
        fields: ['summary']
      }
      body[:nextPageToken] = next_page_token if next_page_token

      response = connection.post('/rest/api/3/search/jql') do |req|
        req.body = body.to_json
      end

      unless response.success?
        puts "Jira API error (#{label}): #{response.status} - #{response.body}"
        return 0
      end

      data = JSON.parse(response.body)
      issues = data['issues'] || []
      count += issues.length

      next_page_token = data['nextPageToken']
      break if data['isLast'] || next_page_token.nil? || issues.empty?
    end

    puts "#{label}: #{count}"
    count
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
