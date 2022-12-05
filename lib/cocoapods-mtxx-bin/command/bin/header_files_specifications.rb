require 'cocoapods-mtxx-bin/helpers/buildAll/builder'
require 'cocoapods-mtxx-bin/helpers/buildAll/podspec_util'
require 'cocoapods-mtxx-bin/helpers/buildAll/zip_file_helper'
require 'cocoapods-mtxx-bin/helpers/buildAll/bin_helper'
require 'cocoapods-mtxx-bin/config/config'
require 'xcodeproj'
require 'yaml'
require 'digest'

module Pod
  class Command
    class Bin < Command
      class HeaderFilesSpecifications < Bin
        self.summary = '规范组件在壳工程使用方式，非<>引入头文件会提示修改，同时会检查壳工程不在参与编译的文件并提示删除'
        self.description = <<-DESC
          #{summary}
        DESC

        def self.options
          [
            %w[--xcodeproj-path xcodeproj路径，默认会查找podfile同级目录下的xcodeproj_path],
            %w[--classes-path 壳工程默认的代码文件路径，默认会查找podfile同级目录下的Classes目录],
            %w[--error-del 提示不规范的组件头文件引入，并删除壳工程不参与编译的文件],
            %w[--ignore-header header白名单设置，也可以在BinConfig.yml里配置，比如壳工程中的协议.h,或者纯.h文件，多个文件用;分割,例如CanvasProtocol.h;PainterProtocol.h]
          ].concat(super).uniq
        end

        def initialize(argv)
          @xcodeproj_path = argv.option('xcodeproj_path', "")
          @classes_path = argv.option('classes_path', "")
          @error_del = argv.flag?('error-del', false)
          @ignore_header = argv.option('ignore-header', '')
          super
        end

        def run
          # 开始时间
          @start_time = Time.now.to_i
          # 读取配置文件
          read_config
          #xcodeproj_path为空字符串，默认获取当前目录下的xxx.xcodeproj
          # 获取xcodeproj_path
          if @xcodeproj_path.empty?
            files = `ls`
            file_list = files.split("\n")
            xcodeproj = file_list.find_all { |n| n.include? ".xcodeproj" }[0]
            scheme = xcodeproj.split(".")[0]
            @xcodeproj_path = File.join(Pod::Config.instance.project_root, xcodeproj)
          end

          if !@xcodeproj_path.include? ".xcodeproj"
            UI.info ".xcodeproj 路径不存在".red
            return
          end
          # 获取xcodeproj 中的 Compile Sources 实际参与编译的文件
          project = Xcodeproj::Project.open(@xcodeproj_path)
          target = project.targets.select { |a_target| a_target.name.eql?(scheme) }[0]
          files = target.source_build_phase.files
          #获取 Compile Sources 中的所有文件名称
          names = Array.new
          files.each do |reference|
            if reference.respond_to? 'file_ref' and reference.file_ref.respond_to? 'path'
              names << reference.file_ref.path
            else
              puts reference
            end
          end
          # puts names
          #过滤出 .m 和 .mm 文件名
          find_names = names.find_all { |n| (n.respond_to? 'include?' and (n.include? ".m" or n.include? ".mm")) }
          find_swift_names = names.find_all { |n| (n.respond_to? 'include?' and n.include? ".swift") }
          if @classes_path.empty?
            @classes_path = File.join(Pod::Config.instance.project_root, "Classes")
          end

          if File.exist?(@classes_path)
            files_h = `find #{@classes_path}  -name "*.h"`
            files_m = `find #{@classes_path}  -name "*.m"`
            files_swift = `find #{@classes_path}  -name "*.swift"`
            file_h_list = files_h.split("\n")
            file_m_list = files_m.split("\n")
            file_s_list = files_swift.split("\n")
            del_h_path_list = Array.new
            save_h_path_list = Array.new
            del_m_path_list = Array.new
            save_m_path_list = Array.new
            del_s_path_list = Array.new
            #获取在Compile Sources 的.h 和 本地路径下不在Compile Sources 的.h（需要删除的）
            file_h_list.each do |file_h_path|
              is_save = false
              find_names.each { |name|
                name_to = ''
                if name.include? '.mm'
                  name_to = name.sub(".mm", ".h")
                elsif name.include? '.m'
                  name_to = name.sub(".m", ".h")
                else
                  puts "error:------#{name}"
                end

                if file_h_path.include? name_to
                  is_save = true
                  break
                end
              }
              if is_save
                save_h_path_list << file_h_path
              else
                del_h_path_list << file_h_path
              end
            end
            #获取在Compile Sources 的.m .mm 和 本地路径下不在Compile Sources 的.m .mm（需要删除的）
            file_m_list.each do |file_m_path|
              is_save = false
              find_names.each { |name|
                if file_m_path.include? name
                  is_save = true
                  break
                end
              }
              if is_save
                save_m_path_list << file_m_path
              else
                del_m_path_list << file_m_path
              end
            end
            #获取在Compile Sources 的.swift 和 本地路径下不在Compile Sources 的.swift（需要删除的）
            file_s_list.each do |file_s_path|
              is_save = false
              find_swift_names.each { |name|
                if file_s_path.include? name
                  is_save = true
                  break
                end
              }
              if !is_save
                del_s_path_list << file_s_path
              end
            end

            # puts "del_h_path_list"
            # puts del_h_path_list
            # puts "save_h_path_list"
            # puts save_h_path_list
            # puts "del_m_path_list"
            UI.title "提示: 壳工程不参与编译的文件，由于之前下层组件，删除引用并未删除代码文件或者其他分支又合入的不在使用或者已经下沉到组件的代码文件".green
            del_m_path_list.each { |name| UI.info "- #{name}".red }
            del_s_path_list.each { |name| UI.info "- #{name}".red }
            # puts "save_m_path_list"
            # puts save_m_path_list
            if @error_del
              del_m_path_list.each { |path|
                h_path = path.gsub(".m", ".h")
                if File.exist?(h_path)
                  `rm  -rf #{h_path}`
                end
                `rm  -rf #{path}`
              }

              del_s_path_list.each { |path|
                `rm  -rf #{path}`
              }
            end

            header_path = save_h_path_list.join(sep = "#",)
            all_header_list = Array.new
            all_header_annotation_list = Array.new
            save_h_path_list.each { |h_path|
              list = `cat #{h_path} | grep '#import "' | awk -F ' ' '{print $2}'`
              list_annotation = `cat #{h_path} | grep '//#import' | awk -F ' ' '{print $2}'`
              #注释的头文件
              list_annotation.split("\n").each { |name|
                if !name.include? "-Swift.h\"" and name.include? ".h\""
                  all_header_annotation_list << name.gsub("\"", "")
                end
              }
              list.split("\n").each { |name|
                if !name.include? "-Swift.h\"" and name.include? ".h\""
                  all_header_list << name.gsub("\"", "")
                end
              }
            }
            save_m_path_list.each { |m_path|
              list = `cat #{m_path} | grep '#import "' | awk -F ' ' '{print $2}'`
              list_annotation = `cat #{m_path} | grep '//#import' | awk -F ' ' '{print $2}'`
              list_annotation.split("\n").each { |name|
                if !name.include? "-Swift.h\"" and name.include? ".h\""
                  all_header_annotation_list << name.gsub("\"", "")
                end
              }
              list.split("\n").each { |name|
                if !name.include? "-Swift.h\"" and name.include? ".h\""
                  all_header_list << name.gsub("\"", "")
                end
              }
            }

            modified_header_file_list = Array.new
            all_header_annotation_list_to = all_header_annotation_list.uniq
            all_header_list_to = all_header_list.uniq

            all_header_del_list = Array.new

            all_header_list_to.each { |name|
              is_unsave = true
              all_header_annotation_list_to.each { |name_to|
                if name == name_to
                  is_unsave = false
                  break
                end
              }
              if is_unsave
                all_header_del_list << name
              end
            }

            UI.title "提示: 使用方式需要调整为<>方式的头文件，请在壳工程代码搜索并修改".green
            if !@ignore_header.empty?
              @ignore_header.split(";").each { |name|
                @ignore_header_list << name
              }
            end
            @ignore_header_list.uniq
            all_header_del_list.each { |name|
              if !header_path.include? name and !@ignore_header_list.include? name
                modified_header_file_list << name
                UI.info "- #{name} 头文件不能在壳工程使用 #import \"#{name}\" 需要修改成#import <xxx/#{name}.h>".red
              end
            }

          end

          # 计算耗时
          show_cost_time
        end

        private

        # 读取配置文件
        def read_config
          UI.title 'Read config from file `BinConfig.yaml`'.green do
            config_file = File.join(Pod::Config.instance.project_root, 'BinConfig.yaml')
            return unless File.exist?(config_file)
            config = YAML.safe_load(File.open(config_file))
            return if config.nil?
            build_config = config['build_config']
            return if build_config.nil?
            @ignore_header_list = build_config['ignore_header_list']
          end
        end

        # 打印耗时
        def show_cost_time
          return if @start_time.nil?
          UI.info "总耗时：#{Time.now.to_i - @start_time}s".green
        end

      end
    end
  end
end

