Pod::Spec.new do |s|
  s.name        = "TCNClient"
  s.version     = "1.0.3"
  s.summary     = "The iOS client library for the TCN protocol."
  s.homepage    = "https://github.com/seriyvolk83/tcn-client-ios"
  s.license          = { :type => 'Apache', :file => 'LICENSE' }
  s.author           = { 'Zsombor Szabo' => 'zsombor@gmail.com' }

  s.requires_arc = true
  s.swift_version = "5.0"
  s.ios.deployment_target = "10.0"
  s.source   = { :git => "https://github.com/seriyvolk83/tcn-client-ios.git", :tag => s.version }
  s.source_files = 'Sources/TCNClient/**/*'
  s.dependency 'CCurve25519'

end

