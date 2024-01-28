$:.unshift(File.expand_path('./lib', ENV['rvm_path']))
require "bundler/capistrano"

server "192.168.0.1", :web, :app, :db, primary: true

set :application, "application"
set :user, "user"
set :deploy_to, "/home/#{user}/apps/#{application}"
set :deploy_via, :remote_cache
set :use_sudo, false

set :scm, "git"
set :repository, "git@bitbucket.org:<user>/#{application}.git"
set :branch, "master"
set :assets_dependencies, %w(app/assets lib/assets vendor/assets Gemfile.lock config/routes.rb)
default_run_options[:pty] = true
ssh_options[:forward_agent] = true

after "deploy", "deploy:cleanup" # keep only the last 5 releases



namespace :deploy do
  %w[start stop restart].each do |command|
    desc "#{command} unicorn server"
    task command, roles: :app, except: {no_release: true} do
      run "/etc/init.d/unicorn_#{application} #{command}"
    end
  end

namespace :assets do

    desc <<-DESC
      Run the asset precompilation rake task. You can specify the full path \
      to the rake executable by setting the rake variable. You can also \
      specify additional environment variables to pass to rake via the \
      asset_env variable. The defaults are:
        set :rake,      "rake"
        set :rails_env, "production"
        set :asset_env, "RAILS_GROUPS=assets"
        set :assets_dependencies, fetch(:assets_dependencies) + %w(config/locales/js)
    DESC
    task :precompile, :roles => :web, :except => { :no_release => true } do
      from = source.next_revision(current_revision)
      if capture("cd #{latest_release} && #{source.local.log(from)} #{assets_dependencies.join ' '} | wc -l").to_i > 0
        run %Q{cd #{latest_release} && #{rake} RAILS_ENV=#{rails_env} #{asset_env} assets:precompile}
      else
        logger.info "Skipping asset pre-compilation because there were no asset changes"
      end
    end

  end
  
  task :setup_config, roles: :app do
    sudo "ln -nfs #{current_path}/config/nginx.conf /etc/nginx/sites-enabled/#{application}"
    sudo "ln -nfs #{current_path}/config/unicorn_init.sh /etc/init.d/unicorn_#{application}"
    run "mkdir -p #{shared_path}/config"
    run "mkdir -p #{shared_path}/public/uploads"
    put File.read("config/database.yml"), "#{shared_path}/config/database.yml"
    puts "Now edit the config files in #{shared_path}."
  end
  after "deploy:setup", "deploy:setup_config"



  task :symlink_config, roles: :app do
    run "ln -nfs #{shared_path}/config/database.yml #{release_path}/config/database.yml"
    run "ln -nfs #{shared_path}/public/uploads  #{release_path}/public/uploads"
  end
  after "deploy:finalize_update", "deploy:symlink_config"

  desc "Make sure local git is in sync with remote."
  task :check_revision, roles: :web do
    unless `git rev-parse HEAD` == `git rev-parse origin/master`
      puts "WARNING: HEAD is not the same as origin/master"
      puts "Run `git push` to sync changes."
      exit
    end
  end
  before "deploy", "deploy:check_revision"
end

# Manual Tasks

namespace :db do

  desc "Syncs the database.yml file from the local machine to the remote machine"
  task :sync_yaml do
    puts "\n\n=== Syncing database yaml to the production server! ===\n\n"
    unless File.exist?("config/database.yml")
      puts "There is no config/database.yml.\n "
      exit
    end
    system "rsync -vr --exclude='.DS_Store' config/database.yml #{user}@#{application}:#{shared_path}/config/"
  end

  desc "Create Production Database"
  task :create do
    puts "\n\n=== Creating the Production Database! ===\n\n"
    run "cd #{current_path}; rake db:create RAILS_ENV=production"
    system "cap deploy:set_permissions"
  end

  desc "Migrate Production Database"
  task :migrate do
    puts "\n\n=== Migrating the Production Database! ===\n\n"
    run "cd #{current_path}; rake db:migrate RAILS_ENV=production"
    system "cap deploy:set_permissions"
  end

  desc "Resets the Production Database"
  task :migrate_reset do
    puts "\n\n=== Resetting the Production Database! ===\n\n"
    run "cd #{current_path}; rake db:migrate:reset RAILS_ENV=production"
  end

  desc "Destroys Production Database"
  task :drop do
    puts "\n\n=== Destroying the Production Database! ===\n\n"
    run "cd #{current_path}; rake db:drop RAILS_ENV=production"
    system "cap deploy:set_permissions"
  end

  desc "Moves the SQLite3 Production Database to the shared path"
  task :move_to_shared do
    puts "\n\n=== Moving the SQLite3 Production Database to the shared path! ===\n\n"
    run "mv #{current_path}/db/production.sqlite3 #{shared_path}/db/production.sqlite3"
    system "cap deploy:setup_symlinks"
    system "cap deploy:set_permissions"
  end

  desc "Populates the Production Database"
  task :seed do
    puts "\n\n=== Populating the Production Database! ===\n\n"
    run "cd #{current_path}; rake db:seed RAILS_ENV=production"
  end

end
