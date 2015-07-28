###
Data Download Section

imports from other modules.
wrap in (-> ... apply) to defer evaluation
such that the value can be defined later than this assignment (file load order).
###

# Load utilities
std_ajax_err = -> window.InstructorDashboard.util.std_ajax_err.apply this, arguments
PendingInstructorTasks = -> window.InstructorDashboard.util.PendingInstructorTasks

# Data Download Section
class DataDownload
  constructor: (@$section) ->
    # attach self to html so that instructor_dashboard.coffee can find
    #  this object to call event handlers like 'onClickTitle'
    @$section.data 'wrapper', @
    # gather elements
    @$list_studs_btn = @$section.find("input[name='list-profiles']'")
    @$list_studs_csv_btn = @$section.find("input[name='list-profiles-csv']'")
    @$list_anon_btn = @$section.find("input[name='list-anon-ids']'")
    @$grade_config_btn = @$section.find("input[name='dump-gradeconf']'")
    @$calculate_grades_csv_btn = @$section.find("input[name='calculate-grades-csv']'")

    # response areas
    @$download                        = @$section.find '.data-download-container'
    @$download_display_text           = @$download.find '.data-display-text'
    @$download_request_response_error = @$download.find '.request-response-error'
    @$reports                         = @$section.find '.reports-download-container'
    @$download_display_table          = @$reports.find '.data-display-table'
    @$reports_request_response        = @$reports.find '.request-response'
    @$reports_request_response_error  = @$reports.find '.request-response-error'


    @report_downloads = new ReportDownloads(@$section)
    @instructor_tasks = new (PendingInstructorTasks()) @$section
    @clear_display()

    # attach click handlers
    # The list-anon case is always CSV
    @$list_anon_btn.click (e) =>
      url = @$list_anon_btn.data 'endpoint'
      location.href = url

    # this handler binds to both the download
    # and the csv button
    @$list_studs_csv_btn.click (e) =>
      @clear_display()

      url = @$list_studs_csv_btn.data 'endpoint'
      # handle csv special case
      # redirect the document to the csv file.
      url += '/csv'

      $.ajax
        dataType: 'json'
        url: url
        error: (std_ajax_err) =>
          @$reports_request_response_error.text gettext("Error generating student profile information. Please try again.")
          $(".msg-error").css({"display":"block"})
        success: (data) =>
          @$reports_request_response.text data['status']
          $(".msg-confirm").css({"display":"block"})

    @$list_studs_btn.click (e) =>
      url = @$list_studs_btn.data 'endpoint'

      # Dynamically generate slickgrid table for displaying student profile information
      @clear_display()
      @$download_display_table.text gettext('Loading')

      # fetch user list
      $.ajax
        dataType: 'json'
        url: url
        error: (std_ajax_err) =>
          @clear_display()
          @$download_request_response_error.text gettext("Error getting student list.")
        success: (data) =>
          @clear_display()

          # display on a SlickGrid
          options =
            enableCellNavigation: true
            enableColumnReorder: false
            forceFitColumns: true
            rowHeight: 35

          columns = ({id: feature, field: feature, name: data.feature_names[feature]} for feature in data.queried_features)
          grid_data = data.students

          $table_placeholder = $ '<div/>', class: 'slickgrid'
          @$download_display_table.append $table_placeholder
          grid = new Slick.Grid($table_placeholder, grid_data, columns, options)
          # grid.autosizeColumns()

    @$grade_config_btn.click (e) =>
      url = @$grade_config_btn.data 'endpoint'
      # display html from grading config endpoint
      $.ajax
        dataType: 'json'
        url: url
        error: (std_ajax_err) =>
          @clear_display()
          @$download_request_response_error.text gettext("Error retrieving grading configuration.")
        success: (data) =>
          @clear_display()
          @$download_display_text.html data['grading_config_summary']

    @$calculate_grades_csv_btn.click (e) =>
      @onClickGradeDownload @$calculate_grades_csv_btn, gettext("Error generating grades. Please try again.")

    @$problem_grade_report_csv_btn.click (e) =>
      @onClickGradeDownload @$problem_grade_report_csv_btn, gettext("Error generating problem grade report. Please try again.")

  onClickGradeDownload: (button, errorMessage) ->
      # Clear any CSS styling from the request-response areas
      #$(".msg-confirm").css({"display":"none"})
      #$(".msg-error").css({"display":"none"})
      @clear_display()

      url = button.data 'endpoint'
      $.ajax
        dataType: 'json'
        url: url
        error: (std_ajax_err) =>
          if e.target.name == 'calculate-grades-csv'
            @$reports_request_response_error.text gettext("Error generating grades. Please try again.")
          else if e.target.name == 'get-student-responses'
            @$reports_request_response_error.text gettext("Error getting student responses. Please try again.")
          else if e.target.name == 'ora2-response-btn'
            @$reports_request_response_error.text gettext("Error getting ORA2 responses. Please try again.")
          else if e.target.name == 'course-forums-btn'
            @$reports_request_response_error.text gettext("Error getting Course Forums data. Please try again.")
          else if e.target.name == 'student-forums-btn'
            @$reports_request_response_error.text gettext("Error getting Student Forums data. Please try again.")
          @$reports_request_response_error.text errorMessage
          $(".msg-error").css({"display":"block"})
        success: (data) =>
          @$reports_request_response.text data['status']
          $(".msg-confirm").css({"display":"block"})

  # handler for when the section title is clicked.
  onClickTitle: ->
    # Clear display of anything that was here before
    @clear_display()
    @instructor_tasks.task_poller.start()
    @report_downloads.downloads_poller.start()

  # handler for when the section is closed
  onExit: ->
    @instructor_tasks.task_poller.stop()
    @report_downloads.downloads_poller.stop()

  clear_display: ->
    # Clear any generated tables, warning messages, etc.
    @$download_display_text.empty()
    @$download_display_table.empty()
    @$download_request_response_error.empty()
    @$reports_request_response.empty()
    @$reports_request_response_error.empty()
    # Clear any CSS styling from the request-response areas
    $(".msg-confirm").css({"display":"none"})
    $(".msg-error").css({"display":"none"})


class ReportDownloads
  ### Report Downloads -- links expire quickly, so we refresh every 5 mins ####
  constructor: (@$section) ->

    @$report_downloads_table = @$section.find ".report-downloads-table"
    reports = @$section.find '.reports-download-container'
    @$reports_request_response = reports.find '.request-response'
    @$reports_request_response_error = reports.find '.request-response-error'

    POLL_INTERVAL = 20000 # 20 seconds, just like the "pending instructor tasks" table
    @downloads_poller = new window.InstructorDashboard.util.IntervalManager(
      POLL_INTERVAL, => @reload_report_downloads()
    )

  reload_report_downloads: ->
    endpoint = @$report_downloads_table.data 'endpoint'
    $.ajax
      dataType: 'json'
      url: endpoint
      success: (data) =>
        if data.downloads.length
          @create_report_downloads_table data.downloads
        else
          console.log "No reports ready for download"
      error: (std_ajax_err) => console.error "Error finding report downloads"

  create_report_downloads_table: (report_downloads_data) ->
    @$report_downloads_table.empty()

    options =
      enableCellNavigation: true
      enableColumnReorder: false
      rowHeight: 30
      forceFitColumns: true

    columns = [
      (
        id: 'link'
        field: 'link'
        name: gettext('File Name')
        toolTip: gettext("Links are generated on demand and expire within 5 minutes due to the sensitive nature of student information.")
        sortable: false
        minWidth: 150
        cssClass: "file-download-link"
        formatter: (row, cell, value, columnDef, dataContext) ->
          data_link ='<a class="course-forums-data" href="' + dataContext['url'] + '">' + dataContext['name'] + '</a>'
          if dataContext['name'].indexOf("course_forums") > -1
            graph_button = _.template('<a class="graph-forums"><i class="fa fa-bar-chart"></i> <%= label %></a>',
                {label: 'Graph This'})
          else
            graph_button = ""
          delete_button = _.template('<a class="delete-report"><i class="fa fa-times-circle"></i> <%= label %></a>',
              {label: 'Delete Report'})
          return data_link +  delete_button+ graph_button
      ),
    ]


    $table_placeholder = $ '<div/>', class: 'slickgrid'
    @$report_downloads_table.append $table_placeholder
    grid = new Slick.Grid($table_placeholder, report_downloads_data, columns, options)
    grid.onClick.subscribe(
        (event) =>
            report_url = event.target.href
            if report_url
                # Record that the user requested to download a report
                Logger.log('edx.instructor.report.downloaded', {
                    report_url: report_url
                })
    )
    grid.autosizeColumns()

    $graph_btns = @$section.find(".graph-forums")
    $graph_btns.click (e) =>
      parent = jQuery(e.target.parentElement.parentElement)
      table_row = parent.find(".course-forums-data")
      @$clicked_name = table_row.text()
      @$graph_element = @$section.find ".report-downloads-graph"
      @$graphEndpoint = @$graph_element.data 'endpoint'
      @graph_forums()

    $delete_btns = @$section.find('.delete-report')
    $delete_btns.click (e) =>
      table_row = jQuery(e.target.parentElement.parentElement)
      filename_cell = table_row.find('.course-forums-data')
      file_to_delete = filename_cell.text()
      if confirm gettext 'Are you sure you want to delete the file ' + file_to_delete + '? This cannot be undone.'
        @$delete_element = @$section.find '.report-downloads-delete'
        @$delete_endpoint = @$delete_element.data 'endpoint'
        success_cb = =>
          @remove_row_from_ui table_row
          @display_file_delete_success file_to_delete
        failure_cb = =>
          @display_file_delete_failure file_to_delete
        @delete_report(file_to_delete, success_cb, failure_cb)

  remove_row_from_ui: (row) ->
    row_height = row.height()
    rows_after = row.nextAll()
    row.remove()
    for sib_row in rows_after
      $sib_row = jQuery(sib_row)
      currX = $sib_row.offset().left
      currY = $sib_row.offset().top
      $sib_row.offset(top: currY - row_height, left: currX)

  display_file_delete_success: (file_to_delete) ->
    @$reports_request_response.text gettext('The file ' + file_to_delete + ' was successfully deleted.')
    @$reports_request_response.css({'display': 'block'})
    @$reports_request_response_error.css({'display': 'none'})

  display_file_delete_failure: (file_to_delete) ->
    @$reports_request_response_error.text gettext('Error deleting the file ' + file_to_delete + '. Please try again.')
    @$reports_request_response_error.css({'display': 'block'})
    @$reports_request_response.css({'display': 'none'})

  delete_report: (file_to_delete, success_cb, failure_cb) ->
    $.ajax
      url: @$delete_endpoint
      type: 'POST'
      data: 'filename': file_to_delete
      dataType: 'json'
      success: (data) ->
        success_cb()
      error: (std_ajax_err) =>
        failure_cb()
 
  get_forum_csv: (cb)->
    $.ajax
      dataType: 'json'
      url: @$graphEndpoint
      data: "clicked_on": @$clicked_name
      success: (data) -> cb? null, data
      error: std_ajax_err ->
        cb? gettext('Error getting forum csv')

  # graph forums data
  graph_forums: ->
      @get_forum_csv (error, forums) =>
        if error
          # instead of graph, show the message that the file is missing and to re-generate
          return @show_errors error
        data = forums['data']
        file_name = forums['filename']
        graph_classname = "report-downloads-graph"
        if data == 'failure'
          error_str = "No Data To Graph. The file might have expired; please refresh and try again"
          $(".report-downloads-graph-title").html(error_str)
          $("."+graph_classname).html("");
          return 'No data to Graph'
        # d3_graph_data_download is defined in templates/class_dashboard/d3_graph_data_download.js
        # because it uses d3
        $(".report-downloads-graph-title").html(file_name)
        d3_graph_data_download(data, "report-downloads-graph")
  show_errors: (msg) -> @$error_section?.text msg



# export for use
# create parent namespaces if they do not already exist.
_.defaults window, InstructorDashboard: {}
_.defaults window.InstructorDashboard, sections: {}
_.defaults window.InstructorDashboard.sections,
  DataDownload: DataDownload
