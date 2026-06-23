# frozen_string_literal: true

namespace :demo do
  desc 'Provision a demo account with an admin login and rich sample data (all channels, teams, labels, contacts...)'
  task setup: :environment do
    email = ENV.fetch('DEMO_ADMIN_EMAIL', 'admin@admin.com')
    password = ENV.fetch('DEMO_ADMIN_PASSWORD', 'Admin@123')
    name = ENV.fetch('DEMO_ADMIN_NAME', 'Admin')
    account_name = ENV.fetch('DEMO_ACCOUNT_NAME', 'Demo Company')

    # AccountSeeder/InboxSeeder refuse to run in production unless this is set.
    ENV['ENABLE_ACCOUNT_SEEDING'] = 'true'

    # Ensure installation configs and feature flags are loaded.
    ConfigLoader.new.process

    account = Account.find_or_create_by!(name: account_name)

    user = User.find_by(email: email)
    unless user
      user = User.new(name: name, email: email, password: password, type: 'SuperAdmin')
      user.skip_confirmation!
      user.save!
    end

    AccountUser.find_or_create_by!(account: account, user: user) { |account_user| account_user.role = :administrator }

    # Rich sample data: teams, custom roles, agents, labels, 50 canned responses, and contacts with
    # conversations across every channel type (Website, Facebook, WhatsApp, Email, SMS, API, Telegram, Line...).
    # NOTE: this resets the demo account's existing teams/inboxes/labels/contacts/conversations.
    Seeders::AccountSeeder.new(account: account).perform!

    puts '=================================================================='
    puts ' Demo ready.'
    puts "   Dashboard        : #{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}"
    puts "   Super Admin panel: #{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/super_admin"
    puts "   Login email      : #{email}"
    puts "   Login password   : #{password}"
    puts '=================================================================='
  end
end
