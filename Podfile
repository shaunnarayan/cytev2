# Uncomment the next line to define a global platform for your project

target 'Cyte' do
  platform :macos, '13.0'
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for Cyte
  pod 'SQLite.swift/SQLCipher', '~> 0.14.1'
end

target 'Cyte for iPhone' do
  platform :ios, '16.0'
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for Cyte
  pod 'SQLite.swift/SQLCipher', '~> 0.14.1'
end

target 'CyteRecorder' do
  platform :ios, '16.0'
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for CyteRecorder
  pod 'SQLite.swift/SQLCipher', '~> 0.14.1'
end

post_install do |installer|
  installer.generated_projects.each do |project|
        project.targets.each do |target|
            target.build_configurations.each do |config|
                config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
                config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
             end
        end
 end
end