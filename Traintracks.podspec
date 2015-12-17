Pod::Spec.new do |s|
  s.name         = "Traintracks"
  s.version      = "1.0.0"
  s.summary      = "Traintracks SDK."
  s.homepage     = "https://traintracks.io.com"
  s.license      = { :type => "MIT" }
  s.author       = { "Traintracks" => "dev@traintracks.io" }
  s.source       = { :git => "https://github.com/mentionllc/traintracks-ios-sdk.git", :tag => "v1.0.0" }
  s.platform     = :ios, '5.0'
  s.source_files = 'Traintracks/*.{h,m}'
  s.requires_arc = true
  s.dependency 'FMDB/standard', '~> 2.5'
end
