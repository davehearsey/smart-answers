require_relative "../date_helper"

module SmartAnswer::Calculators
  class MaternityPaternityCalculator
    include DateHelper

    attr_reader :due_date, :expected_week, :qualifying_week, :employment_start, :notice_of_leave_deadline,
      :leave_earliest_start_date, :adoption_placement_date, :ssp_stop,
      :matched_week, :a_employment_start, :leave_type

    attr_accessor :employment_contract, :leave_start_date, :average_weekly_earnings,
      :a_notice_leave, :last_payday, :pre_offset_payday, :pay_date,
        :pay_day_in_month, :pay_day_in_week, :pay_method, :pay_week_in_month, :work_days, :date_of_birth, :awe

    DAYS_OF_THE_WEEK = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    def initialize(match_or_due_date, leave_type = "maternity")
      expected_start = match_or_due_date - match_or_due_date.wday
      qualifying_start = 15.weeks.ago(expected_start)

      @due_date = @match_date = match_or_due_date
      @leave_type = leave_type
      @expected_week = @matched_week = expected_start .. expected_start + 6.days
      @notice_of_leave_deadline = next_saturday(qualifying_start)
      @qualifying_week = qualifying_start .. qualifying_start + 6.days
      @employment_start = 25.weeks.ago(@qualifying_week.last)
      @a_employment_start = 25.weeks.ago(@matched_week.last)
      @leave_earliest_start_date = 11.weeks.ago(@expected_week.first)
      @ssp_stop = 4.weeks.ago(@expected_week.first)

      # Adoption instance vars
      @a_notice_leave = @match_date + 7
    end

    def format_date(date)
      date.strftime("%e %B %Y")
    end

    def format_date_day(date)
      date.strftime("%A, %d %B %Y")
    end

    def payday_offset
      8.weeks.ago(last_payday) + 1
    end

    def relevant_period
      [pre_offset_payday, last_payday]
    end

    def formatted_relevant_period
      relevant_period.map { |p| format_date_day(p) }.join(" and ")
    end

    def leave_end_date
      52.weeks.since(leave_start_date) - 1
    end

    def pay_start_date
      leave_start_date
    end

    def pay_end_date
      pay_duration.weeks.since(pay_start_date) - 1
    end

    def pay_duration
      case leave_type
      when 'paternity', 'paternity_adoption'
        2
      else
        39
      end
    end

    def notice_request_pay
      28.days.ago(pay_start_date)
    end

    # Rounds up at 2 decimal places.
    #
    def statutory_maternity_rate
      average_weekly_earnings.to_f * 0.9
    end

    def statutory_maternity_rate_a
      statutory_maternity_rate
    end

    def statutory_maternity_rate_b
      [current_statutory_rate, statutory_maternity_rate].min
    end

    def earning_limit_rates_birth
      [
        {min: Date.parse("17 July 2009"), max: Date.parse("16 July 2010"), lower_earning_limit_rate: 95},
        {min: Date.parse("17 July 2010"), max: Date.parse("16 July 2011"), lower_earning_limit_rate: 97},
        {min: Date.parse("17 July 2011"), max: Date.parse("14 July 2012"), lower_earning_limit_rate: 102},
        {min: Date.parse("15 July 2012"), max: Date.parse("13 July 2013"), lower_earning_limit_rate: 107},
        {min: Date.parse("14 July 2013"), max: Date.parse("5 April 2014"), lower_earning_limit_rate: 109},
        {min: Date.parse("6 April 2014"), max: Date.parse("5 April 2015"), lower_earning_limit_rate: 111},
        {min: Date.parse("6 April 2015"), max: Date.parse("5 April 2100"), lower_earning_limit_rate: 112} ### Change year in future
      ]
    end

    def lower_earning_limit_birth
      earning_limit_rate = earning_limit_rates_birth.find { |c| c[:min] <= @qualifying_week.last and c[:max] >= @qualifying_week.last }
      (earning_limit_rate ? earning_limit_rate[:lower_earning_limit_rate] : earning_limit_rates_birth.last[:lower_earning_limit_rate])
    end

    def earning_limit_rates_adoption
      [
        {min: Date.parse("3 April 2010"), max: Date.parse("2 April 2011"), lower_earning_limit_rate: 97},
        {min: Date.parse("3 April 2011"), max: Date.parse("31 March 2012"), lower_earning_limit_rate: 102},
        {min: Date.parse("1 April 2012"), max: Date.parse("31 March 2013"), lower_earning_limit_rate: 107},
        {min: Date.parse("1 April 2013"), max: Date.parse("5 April 2014"), lower_earning_limit_rate: 109},
        {min: Date.parse("6 April 2014"), max: Date.parse("5 April 2015"), lower_earning_limit_rate: 111},
        {min: Date.parse("6 April 2015"), max: Date.parse("5 April 2100"), lower_earning_limit_rate: 112} ### Change year in future
      ]
    end

    def lower_earning_limit_adoption
      earning_limit_rate = earning_limit_rates_adoption.find { |c| c[:min] <= @qualifying_week.last and c[:max] >= @qualifying_week.last }
      (earning_limit_rate ? earning_limit_rate[:lower_earning_limit_rate] : 107)
    end

    def lower_earning_limit
      if @leave_type =~ /maternity|paternity/
        lower_earning_limit_birth
      else
        lower_earning_limit_adoption
      end
    end

    def employment_end
      @due_date
    end

    def adoption_placement_date=(date)
      @adoption_placement_date = date
      @leave_earliest_start_date = 14.days.ago(date)
    end

    ## Paternity
    ##
    ## Statutory paternity rate
    def statutory_paternity_rate
      awe = (@average_weekly_earnings.to_f * 0.9).round(2)
      [current_statutory_rate, awe].min
    end

    ## Adoption
    ##
    ## Statutory adoption rate
    def statutory_adoption_rate
      awe = (@average_weekly_earnings.to_f * 0.9).round(2)
      [current_statutory_rate, awe].min
    end

    def pay_period_in_days
      (last_payday + 1 - pre_offset_payday).to_i
    end

    def calculate_average_weekly_pay(pay_pattern, pay)
      @average_weekly_earnings = sprintf("%.5f", (
        case pay_pattern
        when "irregularly"
          pay.to_f / pay_period_in_days * 7
        when "monthly"
          pay.to_f / 2 * 12 / 52
        else
          pay.to_f / 8
        end
      )).to_f # HMRC truncation at 5 places.
    end

    def total_statutory_pay
      paydates_and_pay.map { |h| h[:pay] }.sum.round(2)
    end

    def paydates_and_pay
      paydates = send(:"paydates_#{pay_method}")
      [].tap do |ary|
        paydates.each_with_index do |paydate, index|
          # Pay period includes the date of payment hence the range starts the day after.
          last_paydate = index == 0 ? pay_start_date : paydates[index - 1] + 1
          pay = pay_for_period(last_paydate, paydate)
          ary << { date: paydate, pay: pay } if pay > 0
        end
      end
    end

    def paydates_every_2_weeks
      paydates_every_n_days(14)
    end

    def paydates_every_4_weeks
      paydates_every_n_days(28)
    end

    def paydates_first_day_of_the_month
      start_date = pay_start_date.day == 1 ? pay_start_date : (pay_start_date + 1.month).beginning_of_month
      end_date = (pay_end_date + 1.month).beginning_of_month

      [].tap do |ary|
        start_date.step(end_date) do |d|
          ary << d if d.day == 1
        end
      end
    end

    def paydates_last_day_of_the_month
      start_date = Date.civil(pay_start_date.year, pay_start_date.month, -1)
      end_date = Date.civil(pay_end_date.year, pay_end_date.month, -1)
      [].tap do |ary|
        start_date.step(end_date) do |d|
          ary << d if d.day == Date.new(d.year, d.month, -1).day
        end
      end
    end

    def paydates_last_working_day_of_the_month
      end_date = Date.civil(pay_end_date.year, pay_end_date.month, -1)

      [].tap do |ary|
        pay_start_date.step(end_date) do |d|
          ary << d if d.day == Date.new(d.year, d.month, last_working_day_of_the_month_offset(d)).day
        end
      end
    end

    def paydates_monthly
      end_date = Date.civil(pay_end_date.year, pay_end_date.month, pay_day_in_month)
      end_date = 1.month.since(end_date) if pay_end_date.day > pay_day_in_month
      [].tap do |ary|
        pay_start_date.step(end_date) do |d|
          ary << d if d.day == pay_day_in_month
        end
      end
    end

    alias paydates_specific_date_each_month paydates_monthly

    def paydates_weekly
      [].tap do |ary|
        pay_start_date.step(pay_end_date + 7) do |d|
          ary << d if d.wday == pay_date.wday
        end
      end
    end

    def paydates_weekly_starting
      [].tap do |ary|
        pay_start_date.step(pay_end_date) do |d|
          ary << d if d.wday == (pay_start_date - 1).wday and d > pay_start_date
        end
      end
    end

    def paydates_a_certain_week_day_each_month
      [].tap do |ary|
        months_between_dates(pay_start_date, pay_end_date).each do |date|
          weekdays = weekdays_for_month(date, pay_day_in_week)
          ary << weekdays.send(pay_week_in_month)
        end
        if ary.last and ary.last < pay_end_date
          weekdays = weekdays_for_month(1.month.since(pay_end_date), pay_day_in_week)
          ary << weekdays.send(pay_week_in_month)
        end
      end
    end

    def statutory_rate(date)
      rates = [
        { min: uprating_date(2012), max: uprating_date(2013), amount: 135.45 },
        { min: uprating_date(2013), max: uprating_date(2014), amount: 136.78 },
        { min: uprating_date(2014), max: uprating_date(2015), amount: 138.18 },
        { min: uprating_date(2014), max: uprating_date(2100), amount: 139.58 } ### Change year in future
      ]
      rate = rates.find { |r| r[:min] <= date and date < r[:max] } || rates.last
      rate[:amount]
    end

    def current_statutory_rate
      statutory_rate(Date.today)
    end

  private

    def paydates_every_n_days(days)
      [].tap do |ary|
        (pay_date..40.weeks.since(pay_date)).step(days).each do |d|
          ary << d
        end
      end
    end

    def months_between_dates(start_date, end_date)
      start_date.beginning_of_month.step(end_date.beginning_of_month).select do |date|
        date.day == 1
      end
    end

    def within_pay_date_range?(day)
      pay_start_date <= day and day <= pay_end_date
    end

    def rate_changes?(week)
      rate_for(week.first) != rate_for(week.last)
    end

    def pay_for_period(start_date, end_date)
      pay = 0.0
      (start_date..end_date).each_slice(7) do |week|
        if week.size < 7 or !within_pay_date_range?(week.last) or rate_changes?(week)
          # When calculating a partial SMP pay week divide the weekly rate by 7
          # truncating the result at 5 decimal places and increment the total pay
          # for each day of the partial week
          week.each do |day|
            if within_pay_date_range?(day)
              pay += sprintf("%.5f", (rate_for(day) / 7)).to_f
            end
          end
        else
          # When calculating a full SMP pay week round up the weekly rate at the second decimal place
          pay += BigDecimal.new(rate_for(week.first).to_s).round(2, BigDecimal::ROUND_UP).to_f
        end
      end
      # HMRC rules stipulate rounding up at 2 decimal places.
      BigDecimal.new(pay.to_s).round(2, BigDecimal::ROUND_UP).to_f
    end

    # Gives the weekly rate for a date.
    def rate_for(date)
      if leave_type == 'maternity'
        maternity_rate_for(date)
      elsif leave_type == 'adoption'
        adoption_rate_for(date)
      else
        paternity_rate_for(date)
      end
    end

    def adoption_rate_for(date)
      awe = (@average_weekly_earnings.to_f * 0.9).round(2)
      if date < 6.weeks.since(leave_start_date) && @match_date >= Date.parse('5 April 2015')
        awe
      else
        [statutory_rate(date), awe].min
      end
    end

    def maternity_rate_for(date)
      if date < 6.weeks.since(leave_start_date)
        statutory_maternity_rate_a
      else
        [statutory_rate(date), statutory_maternity_rate_a].min
      end
    end

    def paternity_rate_for(date)
      awe = (@average_weekly_earnings.to_f * 0.9).round(2)
      [statutory_rate(date), awe].min
    end

    def first_sunday_in_month(month, year)
      weekdays_for_month(Date.civil(year, month, 1), 0).first
    end

    def uprating_date(year)
      date = first_sunday_in_month(4 , year)
      date += leave_start_date.wday if leave_start_date
      date
    end

    def weekdays_for_month(date, weekday)
      date.beginning_of_month.step(date.end_of_month).select do |iter_date|
        weekday == iter_date.wday
      end
    end

    # Calculate the minus offset from the end of the month
    # for the last working day.
    def last_working_day_of_the_month_offset(date)
      ldm = Date.new(date.year, date.month, -1) # Last day of the month.
      ldm_index = ldm.wday
      offset = -1
      while !work_days.include?(ldm_index)
        ldm_index > 0 ? ldm_index -= 1 : ldm_index = 6
        offset -= 1
      end
      offset
    end
  end
end
