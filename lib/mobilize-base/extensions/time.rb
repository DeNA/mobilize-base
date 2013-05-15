class Time
  def Time.at_marks_ago(number=1, unit='day', mark='0000')
    curr_time = Time.now.utc
    #strip out non-numerical characters from mark, add colon
    mark = mark.gsub(/[^0-9]/i,"").rjust(4,'0').ie{|m| [m[0..1],":",m[-2..-1]].join}
    #if user passes in 0 for the number, make it 1
    number = (number.to_i <= 0 ? 1 : number.to_i)
    if unit == 'day'
      curr_mark_time = Time.parse(curr_time.strftime("%Y-%m-%d #{mark} UTC"))
    elsif unit == 'hour'
      if curr_time.strftime("%H%M").to_i > mark.to_i
        curr_mark_time = Time.parse(curr_time.strftime("%Y-%m-%d %H:#{mark[-2..-1]} UTC"))
      end
    end
    #last mark time is 
    mark_ago_increment = (curr_time > curr_mark_time ? (number-1).send(unit) : number.send(unit))
    last_mark_time = curr_mark_time - mark_ago_increment
    return last_mark_time
  end
end
