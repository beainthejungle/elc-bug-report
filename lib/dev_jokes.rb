# frozen_string_literal: true

require 'yaml'
require 'date'

class DevJokes
  JOKES_PATH = File.expand_path('../config/dev_jokes.yml', __dir__)

  def initialize
    @jokes = load_jokes
  end

  # Get a joke based on week number (consistent within the same week)
  def joke_of_the_week
    return nil if @jokes.empty?

    week_number = Date.today.cweek
    year = Date.today.year

    # Use week + year as seed for consistent joke per week
    index = (week_number + year) % @jokes.length
    @jokes[index]
  end

  # Get a random joke (for testing)
  def random_joke
    @jokes.sample
  end

  # Format the joke for Slack
  def format
    joke = joke_of_the_week
    return nil unless joke

    emoji = joke['emoji'] || '😄'
    question = joke['question']
    answer = joke['answer']

    "#{question}\n_#{answer}_ #{emoji}"
  end

  def count
    @jokes.length
  end

  private

  def load_jokes
    return [] unless File.exist?(JOKES_PATH)

    data = YAML.load_file(JOKES_PATH)
    data&.dig('jokes') || []
  rescue StandardError => e
    warn "Failed to load jokes: #{e.message}"
    []
  end
end
