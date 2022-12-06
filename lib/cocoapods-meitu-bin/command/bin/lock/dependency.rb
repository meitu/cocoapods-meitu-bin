
module Pod
  class Command
    class Bin < Command
      class Lock < Bin
        class Dependency < Lock
          include Pod

          self.summary = '分析`POD_NAME`依赖的库'
          self.description = <<-DESC
#{self.summary}，如果加上`--reverse`，则分析依赖`POD_NAME`的库
          DESC

          self.arguments = [
            CLAide::Argument.new('POD_NAME', true)
          ]

          def self.options
            [
              %w[--reverse 分析依赖`POD_NAME`的库]
            ].concat(super).uniq
          end

          def initialize(argv)
            super
            @pod_name = argv.shift_argument
            @reverse = argv.flag?('reverse', false)
          end

          def run
            super
            raise Informative, "请输入Pod库名称，如：AFNetworking" if @pod_name.nil?
            if @reverse
              reverse_dependencies
            else
              dependencies
            end
          end

          def dependencies
            deps = []
            @analyze_result.specifications.map do |spec|
              if spec.root.name == @pod_name
                deps.concat(spec.dependencies)
              end
            end
            UI.puts "\n"
            if deps.empty?
              UI.puts "`#{@pod_name}`无依赖的库".red
            else
              deps.reject! { |dep| dep.root_name == @pod_name }
              unless deps.nil?
                deps.uniq!
              end
              if deps.nil? or deps.empty?
                UI.puts "`#{@pod_name}`无依赖的库".red
              else
                UI.puts "`#{@pod_name}`依赖的库如下：".yellow
                deps.map { |dep| UI.puts "- #{dep}" }
                UI.puts "total #{deps.size} deps".green
              end
            end
          end

          def reverse_dependencies
            pods = []
            @analyze_result.specifications.map do |spec|
              spec.dependencies.map do |dep|
                if dep.root_name == @pod_name and !spec.root.name.include?(@pod_name)
                  pods << spec.root.name
                  break
                end
              end
            end
            UI.puts "\n"
            if pods.empty?
              UI.puts "没有依赖`#{@pod_name}`的库".red
            else
              pods.uniq!
              UI.puts "依赖`#{@pod_name}`的库如下：".yellow
              pods.map { |pod| UI.puts "- #{pod}" }
              UI.puts "total #{pods.size} pods".green
            end
          end
        end
      end
    end
  end
end