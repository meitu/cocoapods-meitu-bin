require 'parallel'

module Pod
  class Command
    class Bin < Command
      class Repo < Bin
        class Update < Repo
          self.summary = '更新私有源'

          self.arguments = [
            CLAide::Argument.new('NAME', false)
          ]

          def self.options
            [
              ['--all', '更新所有私有源，默认只更新二进制相关私有源']
            ].concat(super)
          end

          def initialize(argv)
            @all = argv.flag?('all')
            @name = argv.shift_argument
            super
          end

          def run
            if @all
              config.sources_manager.update()
            else
              valid_sources.map { |source|
                UI.puts "更新私有源仓库 #{source.to_s}"
                source.update(false)
              }
            end
          end


        end
      end
    end
  end
end
