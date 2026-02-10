# frozen_string_literal: true

require_relative 'fun_facts'

class ReportBuilder
  TEAM_ICONS = {
    'Contracts' => ':memo:',
    'OffOnBoarding' => ':rocket:',
    'Organizations' => ':office:'
  }.freeze

  def initialize(team_data, config)
    @team_data = team_data
    @config = config
    @fun_facts = FunFacts.new
  end

  def build
    total_bugs = @team_data.values.sum { |d| d[:bugs].size }
    total_chores = @team_data.values.sum { |d| d[:chores].size }

    lines = []
    lines << ":bug: *ELC Bug Report* :bug:"
    lines << ""
    lines << "*Total Open Issues:* #{total_bugs} bugs, #{total_chores} chores"
    
    # Add fun fact for total if available
    fun_fact = @fun_facts.for_number(total_bugs + total_chores)
    lines << "_#{fun_fact}_" if fun_fact
    
    lines << ""
    lines << "*Breakdown by Squad:*"
    lines << ""

    @team_data.each do |team_name, data|
      icon = TEAM_ICONS[team_name] || ':small_blue_diamond:'
      bugs_count = data[:bugs].size
      chores_count = data[:chores].size
      
      lines << "#{icon} *#{team_name}*: #{bugs_count} bugs, #{chores_count} chores"
      
      # Add fun fact for team if available
      team_fact = @fun_facts.for_number(bugs_count)
      lines << "   _#{team_fact}_" if team_fact && bugs_count > 0
    end

    lines << ""
    lines << build_jira_links
    lines << ""
    lines << "_Generated at #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}_"

    lines.join("\n")
  end

  private

  def build_jira_links
    base_url = @config.dig('jira', 'base_url')
    squad_field = @config.dig('jira', 'squad_field') || 'customfield_10041'
    
    all_squads = @config['teams'].values.flatten.uniq
    squad_filter = all_squads.map { |s| "\"#{s}\"" }.join(', ')
    
    bugs_jql = "issuetype = Bug AND \"#{squad_field}\" IN (#{squad_filter}) AND status NOT IN (Done, Closed, Resolved)"
    chores_jql = "issuetype = Chore AND \"#{squad_field}\" IN (#{squad_filter}) AND status NOT IN (Done, Closed, Resolved)"
    
    bugs_url = "#{base_url}/issues/?jql=#{URI.encode_www_form_component(bugs_jql)}"
    chores_url = "#{base_url}/issues/?jql=#{URI.encode_www_form_component(chores_jql)}"
    
    ":link: <#{bugs_url}|View all bugs in Jira> | <#{chores_url}|View all chores in Jira>"
  end
end
