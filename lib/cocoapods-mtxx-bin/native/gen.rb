
# hook cocoapods-generate的Gen类和Installer类

module Pod
  class Command
    class Gen < Command

      alias old_run run

      def run
        UI.puts "[pod gen] Running with #{configuration.to_s.gsub("\n", "         \n")}" if configuration.pod_config.verbose?

        # this is done here rather than in the installer so we only update sources once,
        # even if there are multiple podspecs
        update_sources if configuration.repo_update?

        installers = []
        Generate::PodfileGenerator.new(configuration).podfiles_by_spec.each do |spec, podfile|
          installer = Generate::Installer.new(configuration, spec, podfile).install!
          installers << installer
        end

        remove_warnings(UI.warnings)

        installers
      end
    end
  end
end

module Pod
  module Generate
    class Installer

      alias old_install! install!

      def install!
        UI.title "Generating #{spec.name} in #{UI.path install_directory}" do
          clean! if configuration.clean?
          install_directory.mkpath

          UI.message 'Creating stub application' do
            create_app_project
          end

          UI.message 'Writing Podfile' do
            podfile.defined_in_file.open('w') { |f| f << podfile.to_yaml }
          end

          installer = nil
          UI.section 'Installing...' do
            configuration.pod_config.with_changes(installation_root: install_directory, podfile: podfile,
                                                  lockfile: configuration.lockfile, sandbox: nil,
                                                  sandbox_root: install_directory + 'Pods',
                                                  podfile_path: podfile.defined_in_file,
                                                  silent: !configuration.pod_config.verbose?, verbose: false,
                                                  lockfile_path: nil) do
              installer = ::Pod::Installer.new(configuration.pod_config.sandbox, podfile, configuration.lockfile)
              installer.use_default_plugins = configuration.use_default_plugins
              installer.install!
            end
          end

          UI.section 'Performing post-installation steps' do
            should_perform_post_install = if installer.respond_to?(:generated_aggregate_targets) # CocoaPods 1.7.0
                                            !installer.generated_aggregate_targets.empty?
                                          else
                                            true
                                          end
            perform_post_install_steps(open_app_project, installer) if should_perform_post_install
          end

          print_post_install_message
          installer
        end
      end
    end
  end
end