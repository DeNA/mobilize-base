require 'action_mailer'
class Emailer < ActionMailer::Base
  ActionMailer::Base.delivery_method = :smtp
  
  ActionMailer::Base.smtp_settings = {
  :address              => "smtp.gmail.com",
  :port                 => 587,
  :domain               => 'ngmoco.com',
  :user_name            => Gdriver.owner_email,
  :password             => Gdriver.password(Gdriver.owner_email),
  :authentication       => 'plain',
  :enable_starttls_auto => true  }

  def write(subj, 
                    bod="", 
                    recipient=Jobtracker.admin_emails.join(","))
    mail(:from=>Gdriver.owner_email,
         :to=>recipient, 
         :subject=>subj, 
         :body=>bod)
  end
end
