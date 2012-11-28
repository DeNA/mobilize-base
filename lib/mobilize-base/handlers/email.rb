module Mobilize
  require 'action_mailer'
  class Email < ActionMailer::Base
    ActionMailer::Base.delivery_method = :smtp
    
    ActionMailer::Base.smtp_settings = {
    :address              => "smtp.gmail.com",
    :port                 => 587,
    :domain               => Gdrive.domain,
    :user_name            => Gdrive.owner_email,
    :password             => Gdrive.password(Gdrive.owner_email),
    :authentication       => 'plain',
    :enable_starttls_auto => true  }

    def write(subj, 
                      bod="", 
                      recipient=Jobtracker.admin_emails.join(","))
      mail(:from=>Gdrive.owner_email,
           :to=>recipient, 
           :subject=>subj, 
           :body=>bod)
    end
  end
end
