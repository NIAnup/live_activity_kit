#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds (or refreshes) the Live Activity widget extension target in an existing
# Flutter iOS project.
#
# Driven by `dart run live_activity_kit:setup`. It relies on the `xcodeproj`
# gem, which every machine that can run `pod install` already has — CocoaPods
# depends on it — so there is nothing extra to install.
#
#   ruby add_widget_target.rb <project.xcodeproj> <widget_dir> <app_group> \
#                             <deployment_target> <target_name>

require 'xcodeproj'

project_path, widget_dir, app_group, deployment_target, target_name = ARGV
abort('usage: add_widget_target.rb <project> <widget_dir> <app_group> <deployment_target> <target_name>') unless target_name

project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |t| t.name == 'Runner' } || project.targets.first
abort('Could not find the Runner target.') if runner.nil?

runner_bundle_id = runner.build_configurations
                         .map { |c| c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] }
                         .compact
                         .first || 'com.example.app'
runner_bundle_id = runner_bundle_id.sub(/\.RunnerTests$/, '')
development_team = runner.build_configurations
                         .map { |c| c.build_settings['DEVELOPMENT_TEAM'] }
                         .compact
                         .first

changed = false

# ---------------------------------------------------------------------------
# Target
# ---------------------------------------------------------------------------

target = project.targets.find { |t| t.name == target_name }
if target.nil?
  target = project.new_target(
    :app_extension,
    target_name,
    :ios,
    deployment_target,
    nil,
    :swift
  )
  changed = true
  puts "created target #{target_name}"
else
  puts "target #{target_name} already exists — refreshing"
end

# ---------------------------------------------------------------------------
# Sources
#
# Every .swift file in the widget directory belongs to the extension. The tree
# is flat by design, so a plain glob is exact rather than merely convenient.
# ---------------------------------------------------------------------------

group = project.main_group.find_subpath(target_name, true)
group.set_source_tree('SOURCE_ROOT')
group.set_path(widget_dir)

existing = group.files.map { |f| f.path }
Dir.glob(File.join(widget_dir, '*.swift')).sort.each do |path|
  name = File.basename(path)
  file = group.files.find { |f| f.path == name } || group.new_reference(name)
  unless existing.include?(name)
    changed = true
    puts "  + #{name}"
  end
  target.add_file_references([file]) unless target.source_build_phase.files_references.include?(file)
end

# Asset catalog, if the developer adds one later.
assets = Dir.glob(File.join(widget_dir, '*.xcassets')).first
if assets
  name = File.basename(assets)
  ref = group.files.find { |f| f.path == name } || group.new_reference(name)
  target.resources_build_phase.add_file_reference(ref) unless
    target.resources_build_phase.files_references.include?(ref)
end

# Info.plist is referenced by build setting, not compiled — but showing it in
# the navigator is what developers expect.
plist_name = 'Info.plist'
group.new_reference(plist_name) unless group.files.any? { |f| f.path == plist_name }

# ---------------------------------------------------------------------------
# Build settings
# ---------------------------------------------------------------------------

target.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{runner_bundle_id}.#{target_name}"
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['INFOPLIST_FILE'] = "#{widget_dir}/Info.plist"
  settings['CODE_SIGN_ENTITLEMENTS'] = "#{widget_dir}/#{target_name}.entitlements"
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['SKIP_INSTALL'] = 'YES'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  settings['DEVELOPMENT_TEAM'] = development_team if development_team
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
end

# ---------------------------------------------------------------------------
# Embed into the app
# ---------------------------------------------------------------------------

embed_phase = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' } ||
              runner.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }

if embed_phase.nil?
  embed_phase = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
  changed = true
end

unless embed_phase.files_references.include?(target.product_reference)
  build_file = embed_phase.add_file_reference(target.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  changed = true
end

unless runner.dependencies.any? { |d| d.target == target }
  runner.add_dependency(target)
  changed = true
end

# ---------------------------------------------------------------------------
# App Group on the app target
#
# The extension's entitlements file is written by the Dart side; the app's is
# patched there too. All that is left is pointing the build setting at it.
# ---------------------------------------------------------------------------

runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] ||= 'Runner/Runner.entitlements'
end

project.save
puts changed ? 'Xcode project updated.' : 'Xcode project already up to date.'
puts "App Group: #{app_group}"
