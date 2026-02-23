# frozen_string_literal: true

require 'cgi'
require 'date'
require_relative 'dev_jokes'

class ReportBuilder
  PRIORITY_EMOJI = {
    'P0' => '🔴',
    'P1' => '🟡',
    'P2' => '🟢'
  }.freeze

  # Mapping from short priority code to full Jira priority name
  PRIORITY_NAMES = {
    'P0' => 'Highest (P0)',
    'P1' => 'High (P1)',
    'P2' => 'Medium (P2)'
  }.freeze

  TEAM_ICONS = {
    'Contracts' => '📝',
    'OffOnBoarding' => '🚀',
    'Organizations' => '🏢'
  }.freeze

  def initialize(issues, config, weekly_stats: nil, sla_points: nil, dry_run: false)
    @issues = issues
    @config = config
    @teams = config['teams']
    @statuses = config['statuses']
    @jira_url = config.dig('jira', 'base_url')
    @weekly_stats = weekly_stats
    @sla_points = sla_points
    @dry_run = dry_run
    @dev_jokes = DevJokes.new
  end

  # Returns an array of Slack Block Kit blocks
  def build_blocks
    stats = calculate_stats

    blocks = []
    blocks << section_block(build_header)
    blocks << divider_block
    blocks << section_block(build_joke_section)
    blocks << divider_block
    blocks << section_block(build_stats_section(stats))
    blocks << divider_block
    blocks << section_block(build_teams_section(stats))

    blocks
  end

  # Returns plain text for dry-run preview
  def build_text
    stats = calculate_stats
    separator = '───'

    lines = []
    lines << build_header
    lines << ''
    lines << separator
    lines << ''
    lines << build_joke_section
    lines << ''
    lines << separator
    lines << ''
    lines << build_stats_section(stats)
    lines << ''
    lines << separator
    lines << ''
    lines << build_teams_section(stats)

    lines.join("\n")
  end

  private

  def section_block(text)
    {
      type: 'section',
      text: {
        type: 'mrkdwn',
        text: text
      }
    }
  end

  def divider_block
    { type: 'divider' }
  end

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
    date = Date.today.strftime('%-d %b %Y')
    "🐛 *ELC Bug Report* · #{date}"
  end

  def build_joke_section
    joke = @dev_jokes.format
    return '' unless joke

    "🎭 *Joke of the week*\n#{joke}"
  end

  def build_stats_section(stats)
    total_url = build_jql_url(build_all_issues_jql)
    total_link = build_slack_link(total_url, stats[:total].to_s)

    # Priority line
    priority_parts = %w[P0 P1 P2].filter_map do |priority|
      count = stats[:by_priority][priority]
      next if count.zero?

      url = build_jql_url(build_priority_jql(priority))
      "#{PRIORITY_EMOJI[priority]} #{priority}: #{build_slack_link(url, count.to_s)}"
    end

    # Status parts
    status_parts = []
    if stats[:unassigned].positive?
      url = build_jql_url(build_unassigned_jql)
      status_parts << "🪑 #{build_slack_link(url, stats[:unassigned].to_s)} unassigned"
    end
    if stats[:blocked].positive?
      url = build_jql_url(build_blocked_jql)
      status_parts << "🚫 #{build_slack_link(url, stats[:blocked].to_s)} blocked"
    end

    # Header line with SLA
    header = "📊 *#{total_link} open issues*"
    if @sla_points
      display_points = @sla_points == @sla_points.to_i ? @sla_points.to_i : @sla_points.round(1)
      header += "  🎯 SLA: #{display_points}"
    end

    all_parts = priority_parts + status_parts

    result = "#{header}\n#{all_parts.join('  ·  ')}"

    # Weekly created vs solved
    if @weekly_stats
      created = @weekly_stats[:created]
      solved = @weekly_stats[:solved]

      created_url = build_jql_url(build_created_last_week_jql)
      solved_url = build_jql_url(build_solved_last_week_jql)

      created_link = build_slack_link(created_url, "#{created} created")
      solved_link = build_slack_link(solved_url, "#{solved} solved")

      result += "\n📅 Last week: #{created_link}  ·  #{solved_link}"
    end

    result
  end

  def build_teams_section(stats)
    sorted_teams = stats[:by_team].sort_by { |name, _| name }

    team_lines = sorted_teams.filter_map do |team_name, team_stats|
      next if team_stats[:total].zero?

      build_team_line(team_name, team_stats)
    end

    "👥 *Teams*\n\n#{team_lines.join("\n\n")}"
  end

  def build_team_line(team_name, team_stats)
    squad_values = team_stats[:squad_values]
    team_url = build_jql_url(build_team_jql(squad_values))
    icon = TEAM_ICONS[team_name] || '🔹'
    total_link = build_slack_link(team_url, "#{team_stats[:total]} issues")

    # Priority breakdown
    priority_parts = %w[P0 P1 P2].filter_map do |priority|
      count = team_stats[:by_priority][priority]
      next if count.zero?

      url = build_jql_url(build_team_priority_jql(squad_values, priority))
      "#{PRIORITY_EMOJI[priority]} #{priority}: #{build_slack_link(url, count.to_s)}"
    end

    # Status breakdown
    status_parts = []
    if team_stats[:unassigned].positive?
      url = build_jql_url(build_team_unassigned_jql(squad_values))
      status_parts << "🪑 #{build_slack_link(url, team_stats[:unassigned].to_s)} unassigned"
    end
    if team_stats[:blocked].positive?
      url = build_jql_url(build_team_blocked_jql(squad_values))
      status_parts << "🚫 #{build_slack_link(url, team_stats[:blocked].to_s)} blocked"
    end

    all_parts = priority_parts + status_parts
    "#{icon} *#{team_name}* · #{total_link}\n#{all_parts.join('  ·  ')}"
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
    priority_name = priority_jql_name(priority)
    "#{project_jql} AND #{all_squad_values_jql} AND priority = \"#{priority_name}\" AND resolution = Unresolved"
  end

  def build_team_jql(squad_values)
    "#{project_jql} AND #{squad_values_jql(squad_values)} AND resolution = Unresolved"
  end

  def build_team_priority_jql(squad_values, priority)
    priority_name = priority_jql_name(priority)
    "#{project_jql} AND #{squad_values_jql(squad_values)} AND priority = \"#{priority_name}\" AND resolution = Unresolved"
  end

  def build_team_unassigned_jql(squad_values)
    "#{project_jql} AND #{squad_values_jql(squad_values)} AND resolution = Unresolved AND assignee IS EMPTY"
  end

  def build_team_blocked_jql(squad_values)
    "#{project_jql} AND #{squad_values_jql(squad_values)} AND status IN (#{blocked_statuses_jql})"
  end

  def priority_jql_name(priority)
    custom = @config.dig('jira', 'priority_names')
    if custom && custom[priority]
      custom[priority]
    else
      PRIORITY_NAMES[priority] || priority
    end
  end

  def build_created_last_week_jql
    "#{project_jql} AND #{all_squad_values_jql} AND created >= -1w"
  end

  def build_solved_last_week_jql
    "#{project_jql} AND #{all_squad_values_jql} AND resolved >= -1w"
  end
end
