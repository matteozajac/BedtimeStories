#!/usr/bin/env ruby
# Bundle only the selected app's public SDK configuration. Provider keys stay server-side.
require 'fileutils'
require 'open3'
require 'json'
require 'xcodeproj'

root = File.expand_path('..', __dir__)
source = ARGV.first || File.expand_path('~/Library/Application Support/BedtimeStoriesCloud/config/GoogleService-Info.plist')
json, status = Open3.capture2('/usr/bin/plutil', '-convert', 'json', '-o', '-', source)
raise 'Firebase client configuration is unavailable' unless status.success?
options = JSON.parse(json)
expected = {
  'PROJECT_ID' => 'gen-lang-client-0154884984',
  'GOOGLE_APP_ID' => '1:280562253820:ios:eed3a08d4e7e6a6b677c79',
  'BUNDLE_ID' => 'com.matteozajac.bedtimestories'
}
raise 'Firebase configuration belongs to another app' unless expected.all? { |key, value| options[key] == value }
raise 'Unexpected administrative credential' if options.keys.any? { |key| key.match?(/PRIVATE_KEY|CLIENT_SECRET|REFRESH_TOKEN/i) }
destination = File.join(root, 'Config/GoogleService-Info.plist')
FileUtils.cp(source, destination) unless File.exist?(destination) && File.binread(source) == File.binread(destination)
File.chmod(0o600, destination)

project = Xcodeproj::Project.open(File.join(root, 'BedtimeStories.xcodeproj'))
app = project.targets.find { |target| target.name == 'BedtimeStories' }
raise 'Expected app target is missing' unless app
group = project.main_group.find_subpath('Config', true)
group.path = 'Config'
reference = group.files.find { |file| file.path == 'GoogleService-Info.plist' } || group.new_file('GoogleService-Info.plist')
app.resources_build_phase.add_file_reference(reference, true)
project.targets.each do |target|
  target.build_configurations.each do |configuration|
    configuration.build_settings['BEDTIME_CLOUD_NARRATION_ENABLED'] =
      target == app && configuration.name == 'Internal' ? 'YES' : 'NO'
  end
end
project.save
puts 'Configured narration for Internal only; local and production builds remain disabled.'
