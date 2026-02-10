# frozen_string_literal: true

require 'slack-ruby-client'

class SlackClient
  def initialize(config)
    Slack.configure do |slack_config|
      slack_config.token = config['bot_token']
    end
    @client = Slack::Web::Client.new
  end

  def post_message(channel, text)
    @client.chat_postMessage(
      channel: channel,
      text: text,
      mrkdwn: true
    )
  end
end
