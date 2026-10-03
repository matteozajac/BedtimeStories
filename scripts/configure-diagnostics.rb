#!/usr/bin/env ruby
# Complete native setup for this app's synchronized source groups and existing backend.
require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'BedtimeStories.xcodeproj'))
app = project.targets.find { |target| target.name == 'BedtimeStories' }
local = project.targets.find { |target| target.name == 'BedtimeStoriesLocal' }
raise 'Run the MZAppFoundation setup apply command first' unless app && local

# MZAppFoundation 0.5.1 and the existing backend share the app's Firebase pin.
firebase = project.root_object.package_references.find { |ref| ref.respond_to?(:repositoryURL) && ref.repositoryURL.include?('firebase-ios-sdk') }
firebase.requirement = { 'kind' => 'exactVersion', 'version' => '12.19.2' }

# Keep app-owned Firebase inspection separate from the generated provider composition.
bootstrap_path = File.join(root, '.mzappfoundation', 'Generated', 'MZBootstrap.swift')
bootstrap = File.read(bootstrap_path)
bootstrap = bootstrap.sub('var inventory = FoundationDiagnostics()', 'var inventory = AppFoundationDiagnostics.make()')
bootstrap = bootstrap.gsub('LocalServices.make(', 'AppDiagnosticServices.make(')
raise 'Generated bootstrap has no app-owned diagnostics hook' unless bootstrap.include?('var inventory = AppFoundationDiagnostics.make()')
raise 'Generated bootstrap has no readable local logging hook' unless bootstrap.include?('AppDiagnosticServices.make(')
File.write(bootstrap_path, bootstrap)

local.file_system_synchronized_groups.clear
local.file_system_synchronized_groups.concat(app.file_system_synchronized_groups)
source_group = app.file_system_synchronized_groups.find { |group| group.path == 'BedtimeStories' }
exception = source_group.exceptions.find { |item| item.target == local } || project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
exception.target = local
exception.membership_exceptions = (Array(exception.membership_exceptions) + [
  'CloudNarration/CloudNarrationModel.swift', 'CloudNarration/CloudAppCheckProviderFactory.swift'
]).uniq.sort
source_group.exceptions << exception unless source_group.exceptions.include?(exception)
local.build_configurations.each do |config|
  config.build_settings['PRODUCT_MODULE_NAME'] = 'BedtimeStories'
end

tests = project.targets.find { |target| target.name == 'BedtimeStoriesTests' }
local_tests = project.targets.find { |target| target.name == 'BedtimeStoriesLocalTests' }
unless local_tests
  local_tests = project.new_target(:unit_test_bundle, 'BedtimeStoriesLocalTests', :ios, '27.0')
end
local_tests.file_system_synchronized_groups.clear
local_tests.file_system_synchronized_groups.concat(tests.file_system_synchronized_groups)
project.build_configurations.each do |configuration|
  # Internal is a release configuration even when the original test target has
  # only Debug/Release. Preserve its bundle loader and app host in every lane.
  original = tests.build_configurations.find { |config| config.name == configuration.name } ||
             tests.build_configurations.find { |config| config.name == 'Release' }
  dest = local_tests.build_configurations.find { |config| config.name == configuration.name } ||
         local_tests.add_build_configuration(configuration.name, configuration.type)
  dest.build_settings = Marshal.load(Marshal.dump(original.build_settings))
  dest.build_settings['SUPPORTED_PLATFORMS'] = 'iphonesimulator'
  dest.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.matteozajac.bedtimestories.localtests'
  dest.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/BedtimeStoriesLocal.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/BedtimeStoriesLocal'
  app_config = local.build_configurations.find { |config| config.name == configuration.name }
  dest.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = app_config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']
end
local_tests.add_dependency(local) unless local_tests.dependencies.any? { |dependency| dependency.target == local }

# Tests import only the foundation interface and use recording sinks.
foundation = project.root_object.package_references.find { |ref| ref.respond_to?(:repositoryURL) && ref.repositoryURL.include?('MZAppFoundation') }
[tests, local_tests].each do |target|
  next if target.package_product_dependencies.any? { |dependency| dependency.product_name == 'MZAppFoundation' }
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.package = foundation
  dependency.product_name = 'MZAppFoundation'
  target.package_product_dependencies << dependency
  file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  file.product_ref = dependency
  target.frameworks_build_phase.files << file
end
project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(local)
scheme.set_launch_target(local)
scheme.add_test_target(local_tests)
scheme.save_as(project.path, local.name, true)
puts 'Configured isolated local source membership and app tests'
