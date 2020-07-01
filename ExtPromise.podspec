Pod::Spec.new do |s|
  s.name         = "ExtPromise"
  s.version      = "0.0.1"
  s.summary      = "Promise for objC"
  s.homepage     = "https://github.com/Pn-X/ExtPromise"
  s.license      = "MIT" 
  s.author       = { "pn-x" => "pannetez@163.com" }
  s.source       = { :git => "https://github.com/Pn-X/ExtPromise.git", :tag => "#{s.version}" }
  s.source_files  = "Classes", "Classes/**/*"
  s.exclude_files = "Classes/Exclude"
  s.ios.deployment_target = '9.0'
end
