source 'https://github.com/CocoaPods/Specs.git'

platform :ios, '6.0'

xcodeproj 'Traintracks'

pod 'FMDB/standard', '~> 2.5'

post_install do |installer|
  installer.pods_project.targets.each do |target|
    puts target.name
  end
end
