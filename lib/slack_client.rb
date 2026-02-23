# frozen_string_literal: true

require 'slack-ruby-client'

class SlackClient
  def initialize(config)
    Slack.configure do |slack_config|
      slack_config.token = config['bot_token']
    end
    @client = Slack::Web::Client.new
  end

  def post_message(channel, text, blocks: nil)
    params = {
      channel: channel,
      text: text,
      mrkdwn: true
    }
    params[:blocks] = blocks if blocks

    @client.chat_postMessage(**params)
  end
end
