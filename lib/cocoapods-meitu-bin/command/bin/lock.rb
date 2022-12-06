require 'cocoapods-meitu-bin/command/bin/lock/spec_repo'
require 'cocoapods-meitu-bin/command/bin/lock/version'
require 'cocoapods-meitu-bin/command/bin/lock/dependency'

module Pod
  class Command
    class Bin < Command
      class Lock < Bin
        include Pod
        include Config::Mixin

        self.abstract_command = true
        self.summary = '分析 Pod 依赖关系'

        def initialize(argv)
          super
        end

        def run
          # 校验Podfile是否存在
          verify_podfile_exists!
          # 依赖分析
          @analyze_result = analyze
        end

        # 依赖分析
        def analyze
          UI.title 'Analyze dependencies'.green do
            analyzer = Pod::Installer::Analyzer.new(config.sandbox, config.podfile, config.lockfile)
            analyzer.analyze(true )
          end
        end
      end
    end
  end
end