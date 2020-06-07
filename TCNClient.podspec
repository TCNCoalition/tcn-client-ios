Pod::Spec.new do |s|
  s.name        = "TCNClient"
  s.version     = "1.0.0"
  s.summary     = "TCNClient"
  s.homepage    = "https://github.com/seriyvolk83/tcn-client-ios"
  s.license     = { :type => "MIT" }
  s.authors     = { "zssz" => "https://github.com/TCNCoalition/tcn-client-ios/commits?author=zssz" }

  s.requires_arc = true
  s.swift_version = "5.1"
  s.ios.deployment_target = "10.0"
  s.source   = { :git => "https://github.com/seriyvolk83/tcn-client-ios.git", :tag => s.version }
  s.source_files = "Source/*.swift"

  s.default_subspec = "Core"

  s.subspec 'Core' do |cs|
    cs.source_files = "Source/*.swift"
  end

end

