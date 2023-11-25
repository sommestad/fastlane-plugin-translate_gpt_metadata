describe Fastlane::Actions::TranslateGptReleaseNotesAction do
  describe '#run' do
    it 'prints a message' do
      expect(Fastlane::UI).to receive(:message).with("The translate_gpt plugin is working!")

      Fastlane::Actions::TranslateGptReleaseNotesAction.run(nil)
    end
  end
end
