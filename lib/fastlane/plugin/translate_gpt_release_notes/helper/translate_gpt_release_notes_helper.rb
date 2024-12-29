require 'fastlane_core/ui/ui'
require 'openai'
require 'json'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    class TranslateGptReleaseNotesHelper
      def initialize(params)
        @params = params
        @client = OpenAI::Client.new(
          access_token: params[:api_token],
          request_timeout: params[:request_timeout]
        )
      end

      # Request a translation from the GPT API
      def translate_text(text, target_locale, platform, max_chars = nil)
        source_locale = @params[:master_locale]

        # Build the translation prompt
        prompt = "# Your role\n"
        prompt += "You are an expert translator specializing in localizing content for apps published on the Apple App Store. You have a deep understanding of cultural nuances and know how to adapt content creatively to fit the target audience and Apple's metadata guidelines.\n\n"
        prompt += "# Your task\n"
        prompt += "Translate or adapt the following text from #{source_locale} to #{target_locale}, creating a subtitle or suffix that fits the character limit while capturing the core message and appeal of the original:\n"
        prompt += "**Source text:**\n"
        prompt += "\"\"\"\n"
        prompt += text
        prompt += "\n\"\"\"\n\n"

        # Add context if provided
        if @params[:context] && !@params[:context].empty?
          prompt += "## Context\n"
          prompt += "\"\"\"\n"
          prompt += @params[:context]
          prompt += "\n\"\"\"\n\n"
        end

        # Add important guidelines
        prompt += "# Important Guidelines:\n"
        prompt += "* If the exact translation cannot fit within the character limit, adapt the subtitle creatively to ensure it is engaging, concise, and culturally relevant.\n"
        prompt += "* Prioritize the app name ('Wisser') as the most important element, with a creative and appealing suffix or subtitle if space allows.\n"
        prompt += "* The translation must not exceed **#{max_chars} characters** (including spaces).\n" if max_chars
        prompt += "* Provide only the final adapted or translated text, strictly adhering to the character limit.\n\n"

        # Print the constructed prompt for debugging
        print prompt

        # API call
        response = @client.chat(
          parameters: {
            model: @params[:model_name] || 'gpt-4o',
            messages: [{ role: "user", content: prompt }],
            temperature: @params[:temperature] || 0.7 # Higher temperature for creative output
          }
        )

        # Handle response
        error = response.dig("error", "message")
        if error
          UI.error "Error translating text: #{error}"
          return nil
        else
          translated_text = response.dig("choices", 0, "message", "content").strip

          # Check if the translated text exceeds the max_chars limit
          if max_chars && translated_text.length > max_chars
            UI.error "Translated text (\"#{translated_text}\") exceeds the max_chars limit (#{max_chars}). Retrying with more emphasis on brevity..."
            return translate_text(text, target_locale, platform, max_chars)
          end

          UI.message "Translated text: #{translated_text}"
          return translated_text
        end
      end

      # Sleep for a specified number of seconds, displaying a progress bar
      def wait(seconds = @params[:request_timeout])
        sleep_time = 0
        while sleep_time < seconds
          percent_complete = (sleep_time.to_f / seconds.to_f) * 100.0
          progress_bar_width = 20
          completed_width = (progress_bar_width * percent_complete / 100.0).round
          remaining_width = progress_bar_width - completed_width
          print "\rTimeout ["
          print Colorizer::code(:green)
          print "=" * completed_width
          print " " * remaining_width
          print Colorizer::code(:reset)
          print "]"
          print " %.2f%%" % percent_complete
          $stdout.flush
          sleep(1)
          sleep_time += 1
        end
        print "\r"
        $stdout.flush
      end
    end

    # Helper class for bash colors
    class Colorizer
      COLORS = {
        black:   30,
        red:     31,
        green:   32,
        yellow:  33,
        blue:    34,
        magenta: 35,
        cyan:    36,
        white:   37,
        reset:   0,
      }

      def self.colorize(text, color)
        color_code = COLORS[color.to_sym]
        "\e[#{color_code}m#{text}\e[0m"
      end
      def self.code(color)
        "\e[#{COLORS[color.to_sym]}m"
      end
    end
  end
end
