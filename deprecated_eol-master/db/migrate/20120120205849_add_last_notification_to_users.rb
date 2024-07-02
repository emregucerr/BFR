class AddLastNotificationToUsers < ActiveRecord::Migration
  def self.up
    add_column :users, :last_notification_at, :datetime, :default => 1.week.ago
    add_column :users, :last_message_at, :datetime, :default => 1.week.ago
  end

  def self.down
    remove_column :users, :last_message_at
    remove_column :users, :last_notification_at
  end
end
