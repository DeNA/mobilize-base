require 'actionmailer'
ActionMailer::Base.delivery_method = :sendmail
class Emailer < ActionMailer::Base
  def Emailer.write(subj, 
                    bod="", 
                    recipient=Jobtracker.admin_emails.join(","))
    mail(:from=>Mobilize::Base.owner_email,
         :to=>recipient, 
         :subject=>subj, 
         :body=>bod)
  end
end
