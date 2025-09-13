class CreateMailJobs < ActiveRecord::Migration[7.1]
  def change
    create_table :mail_jobs do |t|
      t.string :job_id
      t.integer :total_count, null: false
      t.integer :sent_count, default: 0
      t.integer :failed_count, default: 0
      t.integer :status, default: 0
      t.timestamps
    end
    
    add_index :mail_jobs, :job_id
    add_index :mail_jobs, :status
  end
end
