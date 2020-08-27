Pod::Spec.new do |s|

  s.name         = "ZZZombie"
  s.version      = "0.1.0"
  s.summary      = "crash for zombie object"

  s.homepage     = "https://github.com/zhangsuya/ZZZombie.git"
  s.license      = "MIT"
  s.author       = { "zhangsuya" => "792708835@qq.com" }
  s.platform     = :ios, "8.0"
  s.source       = { :git => "https://github.com/zhangsuya/ZZZombie.git", :tag => "#{s.version}" }

  s.requires_arc = false


  s.source_files = ["Source/**/*.{h,m}"]


  
  s.frameworks = "Foundation"

end
