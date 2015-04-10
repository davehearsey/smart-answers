class SmartAnswersController < ApplicationController
  before_action :find_smart_answer
  before_action :redirect_response_to_canonical_url, only: %w{show}
  before_action :set_header_footer_only, only: %w{visualise}

  rescue_from SmartAnswer::FlowRegistry::NotFound, with: :error_404
  rescue_from SmartAnswer::InvalidNode, with: :error_404

  def show
    set_slimmer_artefact(@presenter.artefact)
    respond_to do |format|
      format.html { render }
      format.json {
        html_fragment = with_format('html') {
          render_to_string(partial: "content")
        }
        render json: {
          url: smart_answer_path(params[:id], 'y', @presenter.current_state.responses),
          html_fragment: html_fragment,
          title: @presenter.current_node.title
        }
      }
      format.ics {
        if @presenter.current_node.respond_to?(:calendar) and @presenter.current_node.has_calendar?
          response.headers['Content-Disposition'] = "attachment; filename=\"#{@name.to_s}.ics\""
          render text: @presenter.current_node.calendar.to_ics, layout: false
        else
          error_404
        end
      }
    end

    set_expiry
  end

  def visualise
    respond_to do |format|
      format.html {
        if smartdown_question(@name)
          @graph_presenter = SmartdownAdapter::GraphPresenter.new(@name.to_s)
        else
          @graph_presenter = GraphPresenter.new(@smart_answer)
        end
        @graph_data = @graph_presenter.to_hash
        render layout: true
      }
      format.gv {
        if smartdown_question(@name)
          render text: SmartdownAdapter::GraphvizPresenter.new(@name.to_s).to_gv
        else
          render text: GraphvizPresenter.new(@smart_answer).to_gv
        end
      }
    end
  end


private

  def debug?
    Rails.env.development? && params[:debug]
  end
  helper_method :debug?

  def json_request?
    request.format == Mime::JSON
  end

  def with_format(format, &block)
    old_formats = self.formats
    self.formats = [format]
    result = yield
    self.formats = old_formats
    result
  end

  def find_smart_answer
    @name = params[:id].to_sym
    if smartdown_question(@name)
      @presenter = SmartdownAdapter::Presenter.new(smartdown_flow(@name), request)
    else
      @smart_answer = flow_registry.find(@name.to_s)
      @presenter = SmartAnswerPresenter.new(request, @smart_answer)
    end
  end

  def flow_registry
    @flow_registry = SmartAnswer::FlowRegistry.instance
  end

  def redirect_response_to_canonical_url
    if params[:next] && ! @presenter.current_state.error
      set_expiry
      redirect_params = {
        action:   :show,
        id:        @name,
        started:   "y",
        responses: @presenter.current_state.responses,
        protocol:  (request.ssl? || Rails.env.production?) ? 'https' : 'http',
      }
      if @presenter.current_state.unaccepted_responses
        @presenter.current_state.unaccepted_responses.each_with_index do |unaccepted_response, index|
          redirect_params["previous_response_#{index+1}".to_sym] = unaccepted_response.to_s
        end
      end
      redirect_to redirect_params
    end
  end

  def set_header_footer_only
    set_slimmer_headers(template: 'header_footer_only')
  end

  def smartdown_registry
    @registry ||= SmartdownAdapter::Registry.instance
  end

  def smartdown_question(name)
    smartdown_registry.check(name.to_s)
  end

  def smartdown_flow(name)
    smartdown_registry.find(name.to_s)
  end

end
