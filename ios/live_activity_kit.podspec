Pod::Spec.new do |s|
  s.name             = 'live_activity_kit'
  s.version          = '1.0.0'
  s.summary          = 'Universal Live Activities & Dynamic Island framework for Flutter.'
  s.description      = <<-DESC
Renders Dart-declared component trees as SwiftUI inside a Live Activity widget
extension, and drives ActivityKit from Flutter.
                       DESC
  s.homepage         = 'https://github.com/NIAnup/live_activity_kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Anup Singh' => 'nextautomation.ai@gmail.com' }
  s.source           = { :path => '.' }

  # Classes/  — plugin code, app target only.
  # Shared/   — types that MUST be byte-identical in the widget extension.
  #             `dart run live_activity_kit:setup` copies Shared/ into the
  #             extension; ActivityKit matches attributes by type name, so the
  #             two module-local copies interoperate.
  s.source_files = 'Classes/**/*.swift', 'Shared/**/*.swift'

  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.weak_frameworks = 'ActivityKit', 'WidgetKit', 'SwiftUI'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'SWIFT_VERSION' => '5.0',
  }
  s.swift_version = '5.0'
end
