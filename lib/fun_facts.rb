# frozen_string_literal: true

require 'yaml'

class FunFacts
  FUN_FACTS_PATH = File.expand_path('../config/fun_facts.yml', __dir__)

  def initialize
    @facts = load_facts
  end

  def for_number(number)
    return nil if number.nil? || number.zero?

    @facts[number.to_s] || @facts[number]
  end

  def format(number)
    fact = for_number(number)
    return "_We have *#{number}* open issues to tackle!_" unless fact

    "_We have *#{number}* open issues - #{fact}_"
  end

  private

  def load_facts
    return {} unless File.exist?(FUN_FACTS_PATH)

    YAML.load_file(FUN_FACTS_PATH) || {}
  rescue StandardError
    {}
  end
end
