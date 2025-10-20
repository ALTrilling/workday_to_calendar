(require hyrule *)
(import typer)
(import openpyxl)
(import warnings)
(warnings.filterwarnings "ignore" :category UserWarning :module "openpyxl")
(import icalendar)
(import datetime)
(import itertools)
(import pathlib)
(import numpy :as np)
(import dateutil [rrule])
(import uuid)
(import rich.console [Console])
(import rich.traceback [install])
(setv console (Console))

(defn dbg [#* args #** kwargs]
  (console.log (unpack-iterable args) (unpack-mapping kwargs))
  (get args 0)
)


(defn parse_sheet [fname]
  (setv courses_sheet (as-> fname x
      (openpyxl.load_workbook x)
      (. x active)
  ))

  (setv header_row_num None)
  (for [[i row] (enumerate (.iter_rows courses_sheet :min_row 1) :start 1)]
    ; (console.log i (getattr (get row 1) "value"))

    (as-> (get row 1) x ; Get column B
          (getattr x "value")
          (when (is-not x None) (do (setv header_row_num i) (break)))
    )
  )


  (when (is header_row_num None)
    (raise (ValueError "Couldn't detect the header line"))
  )

  (setv headers (lfor it (get courses_sheet header_row_num) (getattr it "value")))
  (setv (get headers 0) "Long Title")

  (gfor it (.iter_rows courses_sheet :min_row (+ header_row_num 1) :values_only True)
        (dict (zip headers it))
  )
)

(defn main [[folder_name "./sheets"] [output_fname "./events.ics"]]
  (setv folder (pathlib.Path folder_name))
  (unless (and (.exists folder) (.is_dir folder))
    (raise (ValueError f"Folder `{folder_name}` doesn't exist"))
  )
  
  (setv courses (as-> folder x
        (.iterdir x)
        (sorted x)
        (map parse_sheet x)
        (itertools.chain.from_iterable x)
  ))

  (setv days_dict (dict :M "MO"
                        :T "TU"
                        :W "WE"
                        :R "TH"
                        :F "FR"))
  (setv days_vict (np.vectorize (getattr days_dict "get")))
  (setv days_list (list days_dict))

  (setv cal (icalendar.Calendar))
  ; The prodid doesn't actually do anything. It just needs to exist.
  (.add cal "prodid" "-//Auto Generated Calendar//")
  (.add cal "version" "2.0")

  (defn round_to_monday [dt]
    (setv days_since_monday (.weekday dt))
    (- dt (datetime.timedelta :days days_since_monday))
  )

  (for [row courses]
    ; day, time, location
    (setv [d t l] (.split (get row "Meeting Patterns") " | "))
    (setv d (.split d "-"))

    (as-> d x
      (get x 0)
      (.index days_list x)
      (datetime.timedelta :days x)
      (setv day_delta x)
    )

    (as-> (.split t " - ") x
          (lfor it x (.time (datetime.datetime.strptime it "%I:%M %p")))
          (lfor it x (datetime.datetime.combine (get row "Start Date") it))
          ; In fact, this isn't due to the ical format being fucked, it is due to workday giving WRONG FUCKING INFORMATION
          (lfor it x (round_to_monday it))
          (lfor it x (+ it day_delta))
          (setv [sta end] x)
    )

    (setv weekdays (as-> d x
                     (np.array x)
                     (days_vict x)
                     (tuple x)
                   ))

    (setv evt (icalendar.Event))
    (.add evt "description" f"AUTO-GENERATED EVENT\nTaught by `{(get row "Instructor")}`")
    (.add evt "location" l)
    (.add evt "summary" (get row "Section"))
    (.add evt "dtstart" sta)
    (.add evt "dtend"   end)
    (.add evt "rrule" (dict
        :freq "WEEKLY"
        ; If the issue here was me using byweekday (as the docs TOLD ME TO) instead of byday I'm gonna fucking lose it
        ; Update: Oh my fucking god
        :byday weekdays
        :until (get row "End Date")
    ))
    (.add evt "uid" (str (uuid.uuid4)))
    (.add evt "dtstamp" (datetime.datetime.now datetime.UTC))
    (.add_component cal evt)
  )

  (with [f (open output_fname "wb")]
    (as-> (.to_ical cal) x
          (.write f x)
    )
  )
  (console.log f"Successfully wrote from folder `{folder_name}` to file `{output_fname}`")
)

(when (= __name__ "__main__")
  (typer.run main)
)
