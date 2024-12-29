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
      def translate_text(text, target_locale, platform, max_chars = nil, attempt = 1, previous_variants = [])
        source_locale = @params[:master_locale]
        content_type = @params[:content_type]
        app_name = @params[:app_name] if content_type == "name" || content_type == "subtitle" # Include app name where relevant
        content_guidelines = ""

        # Adjust guidelines based on the content type
        case content_type
        when "name"
          content_guidelines += "* The translation must preserve the brand identity and appeal of the app name (#{app_name}).\n"
          content_guidelines += "* Do not exceed **#{max_chars} characters**, including spaces.\n" if max_chars
          content_guidelines += "* Avoid generic or overly descriptive terms; keep it unique and memorable.\n"
        when "subtitle"
          content_guidelines += "* Ensure the subtitle is engaging and clearly conveys the app's core value.\n"
          content_guidelines += "* Modify or adapt creatively to fit the character limit.\n"
          content_guidelines += "* Prioritize brevity and cultural relevance; do not exceed **#{max_chars} characters**, including spaces.\n" if max_chars
          content_guidelines += "* Avoid the following variants, as they are too long: #{previous_variants.join(', ')}.\n" unless previous_variants.empty?
        when "description"
          content_guidelines += "* Maintain a clear, professional tone that explains the app's purpose and features.\n"
          content_guidelines += "* Ensure the translation flows naturally and resonates with the target audience.\n"
          content_guidelines += "* Adhere to the character or word limits where applicable.\n"
        when "keywords"
          content_guidelines += "* Provide a comma-separated list of culturally relevant and app-specific keywords without spaces around commas.\n"
          content_guidelines += "* If the keywords exceed the character limit, prioritize the most relevant keywords and remove less important ones to fit.\n"
        when "release_notes"
          content_guidelines += "* Translate or adapt the release notes to highlight key updates in a concise, user-friendly manner.\n"
          content_guidelines += "* Ensure the tone is approachable and aligned with the app's brand voice.\n"
          content_guidelines += "* Keep the message clear and engaging while respecting any length constraints.\n"
        else
          content_guidelines += "* Follow general translation best practices and ensure the output is culturally relevant.\n"
        end

        # Build the translation prompt
        prompt = "# Your role\n"
        prompt += "You are an expert translator specializing in localizing content for apps published on the Apple App Store. You understand the importance of cultural nuances and adapting content for the target audience while adhering to Apple's metadata guidelines.\n\n"
        prompt += "# Your task\n"
        prompt += "Translate or adapt the following #{content_type} from #{source_locale} to #{target_locale}:\n\n"

        # Add source text
        prompt += "**Source text:**\n"
        prompt += "\"\"\"\n#{text}\n\"\"\"\n\n"

        # Add content-specific guidelines
        prompt += "# Important Guidelines:\n"
        prompt += content_guidelines
        prompt += "* Provide only the final translated or adapted text.\n\n"

        # Debugging: Print the constructed prompt
        print prompt

        # API call
        response = @client.chat(
          parameters: {
            model: @params[:model_name] || 'gpt-4o',
            messages: [{ role: "user", content: prompt }],
            temperature: @params[:temperature] || (content_type == "subtitle" ? 0.7 : 0.3) # Higher temperature for creative tasks
          }
        )

        # Handle response
        error = response.dig("error", "message")
        if error
          UI.error "Error translating text: #{error}"
          return nil
        else
          translated_text = response.dig("choices", 0, "message", "content").strip

          # Ensure the app name is preserved if provided and relevant
          if content_type == "name" && app_name && !translated_text.start_with?(app_name)
            translated_text = "#{app_name}: #{translated_text}"
          end

          # Check if the translated text exceeds the max_chars limit
          if max_chars && translated_text.length > max_chars
            if attempt >= 5
              UI.important "Max attempts reached. Falling back to the original source text."
              return text.gsub(/["']/, "").strip # Strip quotes and trim the source text
            end

            # Add the current failed variant to the previous_variants list
            previous_variants << translated_text

            UI.error "Translated text (\"#{translated_text}\") exceeds the max_chars limit (#{max_chars}). Retrying... (Attempt #{attempt}/5)"
            return translate_text(text, target_locale, platform, max_chars, attempt + 1, previous_variants)
          end

          # Format the translated text for "name" and "subtitle" types
          if %w[name subtitle].include?(content_type)
            translated_text = translated_text.gsub(/["']/, "").strip

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
