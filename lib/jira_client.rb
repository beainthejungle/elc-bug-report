# frozen_string_literal: true

require 'faraday'
require 'json'
require 'base64'

class JiraClient
  def initialize(config)
    @base_url = config['base_url']
    @email = config['email']
    @api_token = config['api_token']
    @squad_field = config['squad_field'] || 'customfield_10041'
  end

  def fetch_bugs(squads)
    jql = build_jql(squads, 'Bug')
    fetch_issues(jql)
  end

  def fetch_chores(squads)
    jql = build_jql(squads, 'Chore')
    fetch_issues(jql)
  end

  private

  def build_jql(squads, issue_type)
    squad_values = squads.map { |s| "\"#{s}\"" }.join(', ')

    "issuetype = #{issue_type} AND " \
    "\"#{@squad_field}\" IN (#{squad_values}) AND " \
    'status NOT IN (Done, Closed, Resolved) ' \
    'ORDER BY priority DESC, created ASC'
  end

  def fetch_issues(jql)
    response = connection.post('/rest/api/3/search/jql') do |req|
      req.body = {
        jql: jql,
        maxResults: 100,
        fields: %w[summary status priority created]
      }.to_json
    end

    if response.success?
      data = JSON.parse(response.body)
      data['issues'] || []
    else
      puts "Warning: Jira API error: #{response.status} - #{response.body}"
      []
    end
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
