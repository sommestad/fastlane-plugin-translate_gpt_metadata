require 'fastlane/action'
require 'openai'
require_relative '../helper/translate_gpt_release_notes_helper'
require 'fileutils'

module Fastlane
  module Actions
    class TranslateGptReleaseNotesAction < Action
      def self.run(params)
        # Define the path for the last run time file
        last_run_file = "last_successful_run_#{params[:input_file]}"

        # Determine if iOS or Android based on the platform
        is_ios = params[:platform] == 'ios'
        base_directory = is_ios ? 'fastlane/metadata' : 'fastlane/metadata/android'

        # Check if the base directory exists before proceeding
        unless Dir.exist?(base_directory)
          UI.error("Directory does not exist: #{base_directory}")
          return
        end

        locales = list_locales(base_directory)
        master_texts, master_file_path = fetch_master_texts(base_directory, params[:master_locale], is_ios, params[:input_file])

        # Skip translation if master texts are not found
        unless master_texts && master_file_path
          UI.message("Master file not found, skipping translation.")
          return
        end

        master_mod_time = File.mtime(master_file_path).to_i

        locales.each do |locale|
          next if locale == params[:master_locale] # Skip master locale

          target_path = is_ios ? File.join(base_directory, locale) : File.join(base_directory, locale, 'changelogs')
          target_file = File.join(target_path, params[:input_file])

          # Skip locale if the translation file exists and is up-to-date
          if File.exist?(target_file) && File.mtime(target_file).to_i >= master_mod_time
            UI.message("Skipping up-to-date translation for locale: #{locale}")
            next
          end

          UI.message("Translating for locale: #{locale}")
          helper = Helper::TranslateGptReleaseNotesHelper.new(params)
          translated_text = helper.translate_text(master_texts, locale, params[:platform], params[:max_chars])

          # Ensure target path exists or create it
          FileUtils.mkdir_p(target_path) unless Dir.exist?(target_path)

          # Write the translated text immediately
          File.write(target_file, translated_text)
          UI.success("Successfully translated and wrote file for locale: #{locale}")
        end

        # Update the last run time
        File.write(last_run_file, Time.now.to_i)
        UI.success("Translation completed successfully.")
      end

      def self.list_locales(base_directory)
        Dir.children(base_directory).select do |entry|
          File.directory?(File.join(base_directory, entry)) && entry != 'review_information' && entry != 'default'
        end
      end

      def self.fetch_master_texts(base_directory, master_locale, is_ios, input_file)
        master_path = is_ios ? File.join(base_directory, master_locale) : File.join(base_directory, master_locale, 'changelogs')

        # Check if the master path exists
        unless Dir.exist?(master_path)
          UI.error("Master path does not exist: #{master_path}")
          return [nil, nil]
        end

        file_path = File.join(master_path, input_file)

        # Check if the file exists before reading
        unless File.exist?(file_path)
          UI.error("File does not exist: #{file_path}")
          return [nil, nil]
        end

        [File.read(file_path), file_path]
      end

      def self.description
        "Translate release notes or changelogs for iOS and Android apps using OpenAI's GPT API"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :api_token,
            env_name: "GPT_API_KEY",
            description: "API token for ChatGPT",
            sensitive: true,
            code_gen_sensitive: true,
            default_value: ""
          ),
          FastlaneCore::ConfigItem.new(
            key: :model_name,
            env_name: "GPT_MODEL_NAME",
            description: "Name of the ChatGPT model to use",
            default_value: "gpt-4-turbo-preview"
          ),
          FastlaneCore::ConfigItem.new(
            key: :request_timeout,
            env_name: "GPT_REQUEST_TIMEOUT",
            description: "Timeout for the request in seconds",
            type: Integer,
            default_value: 30
          ),
          FastlaneCore::ConfigItem.new(
            key: :temperature,
            env_name: "GPT_TEMPERATURE",
            description: "What sampling temperature to use, between 0 and 2",
            type: Float,
            optional: true,
            default_value: 0.5
          ),
          FastlaneCore::ConfigItem.new(
            key: :master_locale,
            env_name: "MASTER_LOCALE",
            description: "Master language/locale for the source texts",
            type: String,
            default_value: "en-US"
          ),
          FastlaneCore::ConfigItem.new(
            key: :platform,
            env_name: "PLATFORM",
            description: "Platform for which to translate (ios or android)",
            is_string: true,
            default_value: 'ios'
          ),
          FastlaneCore::ConfigItem.new(
            key: :context,
            env_name: "GPT_CONTEXT",
            description: "Context for translation to improve accuracy",
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :input_file,
            env_name: "INPUT_FILE_NAME",
            description: "The name of the file to translate (e.g., release_notes.txt, description.txt)",
            type: String,
            default_value: "release_notes.txt"
          ),
          FastlaneCore::ConfigItem.new(
            key: :max_chars,
            env_name: "GPT_MAX_CHARS",
            description: "Maximum character count for each translation",
            type: Integer,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :content_type,
            env_name: "GPT_CONTENT_TYPE",
            description: "Content type",
            type: String,
            optional: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :app_name,
            env_name: "GPT_APP_NAME",
            description: "App name",
            type: String,
            optional: false
          )
        ]
      end

      def self.authors
        ["antonkarliner"]
      end

      def self.is_supported?(platform)
        [:ios, :android].include?(platform)
      end
    end
  end
end
