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

project_path, widget_dir, app_group, deployment_target, target_name, app_deployment_target = ARGV
abort('usage: add_widget_target.rb <project> <widget_dir> <app_group> <deployment_target> <target_name> [app_deployment_target]') unless target_name
app_deployment_target ||= '13.0'

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
  # iOS refuses to install an extension whose Info.plist has no CFBundleVersion
  # or CFBundleShortVersionString ("Failed to create app extension placeholder"),
  # and the App Store requires them to match the host app. Flutter keeps both in
  # Flutter/Generated.xcconfig, which this target is pointed at below; the
  # `default=` operator keeps the bundle valid even if that file is absent
  # (a fresh clone before `flutter pub get`).
  settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER:default=1)'
  settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME:default=1.0.0)'
  settings['DEVELOPMENT_TEAM'] = development_team if development_team
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'

  # Break inheritance of the app's linker flags.
  #
  # A Flutter project's PROJECT-level build configuration is backed by
  # Flutter/*.xcconfig, which pulls in Pods-Runner.*.xcconfig and its
  # `OTHER_LDFLAGS = -framework "Flutter" -framework "live_activity_kit" …`.
  # A new target with no xcconfig of its own inherits all of that and fails to
  # link with "Framework 'Flutter' not found" — the extension is a separate
  # process that must not link Flutter or any plugin pod. Assigning without
  # $(inherited) is what severs the chain; SwiftUI, WidgetKit and ActivityKit
  # are auto-linked by the Swift compiler and need no flags.
  settings['OTHER_LDFLAGS'] = ''
  settings['FRAMEWORK_SEARCH_PATHS'] = '$(PLATFORM_DIR)/Developer/Library/Frameworks'
  settings['HEADER_SEARCH_PATHS'] = ''
  settings['LIBRARY_SEARCH_PATHS'] = ''
  settings['OTHER_SWIFT_FLAGS'] = ''
end

# ---------------------------------------------------------------------------
# Inherit Flutter's version numbers
#
# Flutter/Generated.xcconfig is where FLUTTER_BUILD_NAME and FLUTTER_BUILD_NUMBER
# live, and it is rewritten on every build. Pointing the extension at it keeps
# its version in lockstep with the app automatically, which the App Store
# requires. Generated.xcconfig holds no linker flags, so unlike Flutter/*.xcconfig
# it cannot drag Flutter or the plugin pods into the extension's link line.
# ---------------------------------------------------------------------------

generated_xcconfig = project.files.find do |file|
  file.real_path.to_s.end_with?('Flutter/Generated.xcconfig')
end

if generated_xcconfig
  target.build_configurations.each do |config|
    unless config.base_configuration_reference == generated_xcconfig
      config.base_configuration_reference = generated_xcconfig
      changed = true
    end
  end
  puts 'linked Flutter/Generated.xcconfig for version numbers'
else
  puts 'WARNING: Flutter/Generated.xcconfig not found; extension will use fallback version 1.0.0 (1)'
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

# Order the embed phase BEFORE Flutter's "Thin Binary" script.
#
# Xcode appends new copy phases last, which puts "Embed Foundation Extensions"
# after "Thin Binary". Flutter's script declares Runner.app among its outputs
# while the embed phase writes into Runner.app/PlugIns, so the two form a
# dependency cycle and the build fails with "Cycle inside Runner". Embedding
# first breaks it: the extension is in place before Flutter thins the binary.
thin_index = runner.build_phases.index do |phase|
  phase.respond_to?(:name) && phase.name == 'Thin Binary'
end
embed_index = runner.build_phases.index(embed_phase)

if thin_index && embed_index && embed_index > thin_index
  runner.build_phases.move(embed_phase, thin_index)
  changed = true
  puts 'moved "Embed Foundation Extensions" before "Thin Binary" (breaks build cycle)'
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

# ---------------------------------------------------------------------------
# Deployment target
#
# The pod needs iOS 13 (SwiftUI types in stored properties). Raising only the
# Podfile is not enough: CocoaPods validates against the Podfile platform, but
# Xcode still builds the app target against its own setting, so both have to
# move or the build fails later with a less obvious error.
# ---------------------------------------------------------------------------

def raise_deployment_target(settings, minimum)
  current = settings['IPHONEOS_DEPLOYMENT_TARGET']
  return false if current && current.to_f >= minimum.to_f

  settings['IPHONEOS_DEPLOYMENT_TARGET'] = minimum
  true
end

raised = false
runner.build_configurations.each do |config|
  raised |= raise_deployment_target(config.build_settings, app_deployment_target)
end
project.build_configurations.each do |config|
  raised |= raise_deployment_target(config.build_settings, app_deployment_target)
end

if raised
  changed = true
  puts "raised app deployment target to iOS #{app_deployment_target}"
end

project.save
puts changed ? 'Xcode project updated.' : 'Xcode project already up to date.'
puts "App Group: #{app_group}"
