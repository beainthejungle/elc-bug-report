# frozen_string_literal: true

require 'cgi'
require 'date'
require_relative 'fun_facts'

class ReportBuilder
  PRIORITY_EMOJI = {
    'P0' => '🔴',
    'P1' => '🟡',
    'P2' => '🟢'
  }.freeze

  TEAM_ICONS = {
    'Contracts' => '📝',
    'OffOnBoarding' => '🚀',
    'Organizations' => '🏢'
  }.freeze

  GREETINGS = [
    "*Good morning team!* Let's squash some bugs today!",
    '*Rise and shine, bug hunters!* Time to make our code cleaner!',
    '*Hello team!* Another day, another chance to ship quality code!',
    "*Good morning!* Grab your coffee and let's tackle these bugs!",
    "*Hey team!* Let's make today a great day for bug fixing!",
    '*Morning everyone!* Together we can crush these bugs!',
    "*Good morning!* Let's focus and knock out some bugs today!",
    '*Hello bug busters!* Ready to make our product even better?'
  ].freeze

  SEPARATOR = '-' * 30

  def initialize(issues, config, dry_run: false)
    @issues = issues
    @config = config
    @teams = config['teams']
    @statuses = config['statuses']
    @jira_url = config.dig('jira', 'base_url')
    @dry_run = dry_run
    @fun_facts = FunFacts.new
  end

  def build
    stats = calculate_stats

    lines = []
    lines << build_header
    lines << ''
    lines << GREETINGS.sample
    lines << ''
    lines << @fun_facts.format(stats[:total])
    lines << ''
    lines << SEPARATOR
    lines << ''
    lines << build_summary(stats)
    lines << ''
    lines << SEPARATOR
    lines << ''
    lines << build_priority_breakdown(stats)
    lines << ''
    lines << SEPARATOR
    lines << ''
    lines << build_team_breakdown(stats)
    lines << ''
    lines << "_Generated at #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}_"

    lines.join("\n")
  end

  private

  def calculate_stats
    stats = {
      total: @issues.length,
      bugs: 0,
      chores: 0,
      unassigned: 0,
      assigned: 0,
      blocked: 0,
      by_priority: Hash.new(0),
      by_team: {}
    }

    # Initialize team stats
    @teams.each do |team_name, squad_values|
      stats[:by_team][team_name] = {
        squad_values: squad_values,
        total: 0,
        bugs: 0,
        chores: 0,
        unassigned: 0,
        assigned: 0,
        blocked: 0,
        by_priority: Hash.new(0)
      }
    end

    @issues.each do |issue|
      priority = extract_priority(issue[:priority])
      category = categorize_issue(issue)
      team_name = find_team_name(issue[:squad])
      issue_type = issue[:issue_type]&.downcase

      stats[:by_priority][priority] += 1
      stats[category] += 1
      stats[:bugs] += 1 if issue_type == 'bug'
      stats[:chores] += 1 if issue_type == 'chore'

      next unless team_name && stats[:by_team][team_name]

      team = stats[:by_team][team_name]
      team[:total] += 1
      team[:by_priority][priority] += 1
      team[category] += 1
      team[:bugs] += 1 if issue_type == 'bug'
      team[:chores] += 1 if issue_type == 'chore'
    end

    stats
  end

  def categorize_issue(issue)
    return :blocked if @statuses['blocked'].include?(issue[:status])
    return :unassigned if issue[:assignee].nil? || issue[:assignee].empty?

    :assigned
  end

  def extract_priority(priority_string)
    return 'P2' if priority_string.nil?

    match = priority_string.match(/\(P\d\)/)
    match ? match[0].tr('()', '') : 'P2'
  end

  def find_team_name(squad_value)
    return nil if squad_value.nil?

    @teams.each do |team_name, squad_values|
      return team_name if squad_values.any? { |sv| sv.downcase == squad_value.downcase }
    end
    nil
  end

  def build_header
    date = Date.today.strftime('%d/%m/%Y')
    "🐛 *ELC Bug Report* — #{date}"
  end

  def build_summary(stats)
    total_url = build_jql_url(build_all_issues_jql)
    unassigned_url = build_jql_url(build_unassigned_jql)
    blocked_url = build_jql_url(build_blocked_jql)

    parts = []
    parts << "Total: #{build_slack_link(total_url, stats[:total].to_s)}"
    parts << "Bugs: #{stats[:bugs]}"
    parts << "Chores: #{stats[:chores]}"
    parts << "Unassigned: #{build_slack_link(unassigned_url, stats[:unassigned].to_s)}"
    parts << "Blocked: #{build_slack_link(blocked_url, stats[:blocked].to_s)}"

    "📋 *Summary:* #{parts.join(' | ')}"
  end

  def build_priority_breakdown(stats)
    parts = []

    %w[P0 P1 P2].each do |priority|
      count = stats[:by_priority][priority]
      next if count.zero?

      emoji = PRIORITY_EMOJI[priority]
      url = build_jql_url(build_priority_jql(priority))
      parts << "#{emoji} #{priority}: #{build_slack_link(url, count.to_s)}"
    end

    return '🎯 *By Priority:* No issues!' if parts.empty?

    "🎯 *By Priority:* #{parts.join(' | ')}"
  end

  def build_team_breakdown(stats)
    sorted_teams = stats[:by_team].sort_by { |name, _| name }

    team_lines = sorted_teams.filter_map do |team_name, team_stats|
      next if team_stats[:total].zero?

      squad_values = team_stats[:squad_values]
      team_url = build_jql_url(build_team_jql(squad_values))
      icon = TEAM_ICONS[team_name] || '🔹'

      parts = []
      parts << "#{team_stats[:bugs]} bugs" if team_stats[:bugs] > 0
      parts << "#{team_stats[:chores]} chores" if team_stats[:chores] > 0

      status_parts = []
      if team_stats[:unassigned] > 0
        url = build_jql_url(build_team_unassigned_jql(squad_values))
        status_parts << "Unassigned: #{build_slack_link(url, team_stats[:unassigned].to_s)}"
      end
      if team_stats[:blocked] > 0
        url = build_jql_url(build_team_blocked_jql(squad_values))
        status_parts << "Blocked: #{build_slack_link(url, team_stats[:blocked].to_s)}"
      end

      priority_parts = team_stats[:by_priority].sort.filter_map do |priority, count|
        next if count.zero?

        "#{PRIORITY_EMOJI[priority]} #{count}"
      end

      line = "#{icon} *#{team_name}* (#{build_slack_link(team_url, team_stats[:total].to_s)}): #{parts.join(', ')}"
      line += " | #{status_parts.join(' / ')}" unless status_parts.empty?
      line += " | #{priority_parts.join(' ')}" unless priority_parts.empty?
      line
    end

    "👥 *By Team*\n#{team_lines.join("\n")}"
  end

  def build_jql_url(jql)
    encoded_jql = CGI.escape(jql)
    "#{@jira_url}/issues/?jql=#{encoded_jql}"
  end

  def build_slack_link(url, text)
    return text if @dry_run

    "<#{url}|#{text}>"
  end

  # JQL Builders
  def project_jql
    project = @config.dig('jira', 'project_key') || 'FCT'
    issue_types = (@config.dig('jira', 'issue_types') || %w[Bug Chore]).map { |t| "\"#{t}\"" }.join(', ')
    "project = #{project} AND issuetype IN (#{issue_types})"
  end

  def active_statuses_jql
    @statuses['active'].map { |s| "\"#{s}\"" }.join(', ')
  end

  def blocked_statuses_jql
    @statuses['blocked'].map { |s| "\"#{s}\"" }.join(', ')
  end

  def squad_values_jql(squad_values)
    values = squad_values.map { |s| "\"#{s}\"" }.join(', ')
    squad_field = @config.dig('jira', 'squad_field') || 'squad[Dropdown]'
    "\"#{squad_field}\" IN (#{values})"
  end

  def all_squad_values_jql
    squad_values_jql(@teams.values.flatten)
  end

  def build_all_issues_jql
    "#{project_jql} AND #{all_squad_values_jql} AND resolution = Unresolved"
  end

  def build_unassigned_jql
    "#{project_jql} AND #{all_squad_values_jql} AND resolution = Unresolved AND assignee IS EMPTY"
  end

  def build_blocked_jql
    "#{project_jql} AND #{all_squad_values_jql} AND status IN (#{blocked_statuses_jql})"
  end

  def build_priority_jql(priority)
    "#{project_jql} AND #{all_squad_values_jql} AND priority ~ \"(#{priority})\" AND resolution = Unresolved"
  end

  def build_team_jql(squad_values)
    "#{project_jql} AND #{squad_values_jql(squad_values)} AND resolution = Unresolved"
  end

  def build_team_unassigned_jql(squad_values)
    "#{project_jql} AND #{squad_values_jql(squad_values)} AND resolution = Unresolved AND assignee IS EMPTY"
  end

  def build_team_blocked_jql(squad_values)
    "#{project_jql} AND #{squad_values_jql(squad_values)} AND status IN (#{blocked_statuses_jql})"
  end
end
