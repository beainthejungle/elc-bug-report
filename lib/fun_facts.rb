# frozen_string_literal: true

require 'yaml'

class FunFacts
  FUN_FACTS_PATH = File.expand_path('../../config/fun_facts.yml', __FILE__)

  def initialize
    @facts = load_facts
  end

  def for_number(number)
    return nil if number.nil? || number.zero?

    @facts[number.to_s] || @facts[number]
  end

  private

  def load_facts
    return {} unless File.exist?(FUN_FACTS_PATH)

    YAML.load_file(FUN_FACTS_PATH) || {}
  rescue StandardError
    {}
  end
end
