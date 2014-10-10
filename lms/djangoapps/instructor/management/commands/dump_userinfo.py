# -*- coding: utf-8 -*-
#
# CME management command: dump userinfo to csv files for reporting

import csv
from datetime import datetime
from optparse import make_option
import sys
import tempfile

from django.core.management.base import BaseCommand, CommandError
from django.contrib.auth.models import User
from pytz import UTC

from certificates.models import GeneratedCertificate
from cme_registration.models import CmeUserProfile
from opaque_keys import InvalidKeyError
from opaque_keys.edx.keys import CourseKey
from opaque_keys.edx.locations import SlashSeparatedCourseKey
from shoppingcart.models import PaidCourseRegistration
from student.models import UserProfile

PROFILE_FIELDS = [
    ('last_name', 'Last Name'),
    ('middle_initial', 'Middle Initial'),
    ('first_name', 'First Name'),
    ('email', 'Email Address'),
    ('birth_date', 'Birth Date'),
    ('professional_designation', 'Professional Designation'),
    ('license_number', 'Professional License Number'),
    ('license_country', 'Professional License Country'),
    ('license_state', 'Professional License State'),
    ('physician_status', 'Physician Status'),
    ('patient_population', 'Patient Population'),
    ('specialty', 'Specialty'),
    ('sub_specialty', 'Sub Specialty'),
    ('affiliation', 'Stanford Medicine Affiliation'),
    ('sub_affiliation', 'Stanford Sub Affiliation'),
    ('stanford_department', 'Stanford Department'),
    ('sunet_id', 'SUNet ID'),
    ('other_affiliation', 'Other Affiliation'),
    ('job_title_position_untracked', 'Job Title or Position'),
    ('address_1', 'Address 1'),
    ('address_2', 'Address 2'),
    ('city', 'City'),
    ('state', 'State'),
    ('postal_code', 'Postal Code'),
    ('county_province', 'County/Province'),
    ('country_cme', 'Country'),
    ('phone_number_untracked', 'Phone Number'),
    ('gender', 'Gender'),
    ('marketing_opt_in_untracked', 'Marketing Opt-In'),
]

class Command(BaseCommand):
    help = """Export data required by Stanford SCCME Tracker Project to .csv file."""

    option_list = BaseCommand.option_list + (
        make_option(
            '-c',
            '--course',
            metavar='COURSE_ID',
            dest='course',
            default=False,
            help='The course id (e.g., CME/001/2013-2015) to select from.',
        ),
        make_option(
            '-o',
            '--outfile',
            metavar='OUTFILE',
            dest='outfile',
            default=False,
            help='The file path to which to write the output.',
        ),
    )

    def handle(self, *args, **options):
        course_id = options['course']
        do_all_courses = options['all']
        outfile_name = options['outfile']
        verbose = int(options['verbosity']) > 1

        if do_all_courses:
            raise CommandError('--all is not currently implemented; please use --course')
        if not (do_all_courses or course_id):
            raise CommandError('One of --course or --all must be given')
        elif (do_all_courses and course_id):
            raise CommandError('--course and --all are mutually exclusive')

        try:
            course_id = CourseKey.from_string(course_id)
        except InvalidKeyError:
            course_id = SlashSeparatedCourseKey.from_deprecated_string(course_id)

        outfile = None
        if outfile_name:
            outfile = open(outfile_name, 'wb')
        else:
            outfile = tempfile.NamedTemporaryFile(suffix='.csv', delete=False)
            outfile_name = outfile.name

        csv_fieldnames = [x[1] for x in PROFILE_FIELDS]
        csv_fieldnames.extend(['System ID', 'Date Registered', 'Fee Charged', 'Payment Type', 'Amount Paid',
                               'Reference Number', 'Reference', 'Paid By', 'Dietary Restrictions',
                               'Marketing Source', 'Credits Issued', 'Credit Date', 'Certif'])
        csvwriter = csv.DictWriter(outfile, fieldnames=csv_fieldnames, delimiter=',', quoting=csv.QUOTE_ALL)
        csvwriter.writeheader()

        sys.stdout.write("Fetching enrolled students for {course}...".format(course=course_id))
        enrolled_students = User.objects.filter(courseenrollment__course_id=course_id).prefetch_related("groups").order_by('username')
        sys.stdout.write(" done.\n")

        count = 0
        total = enrolled_students.count()
        start = datetime.now(UTC)
        intervals = int(0.10 * total)
        if intervals > 100 and verbose:
            intervals = 101
        sys.stdout.write("Processing users")

        for student in enrolled_students:

            student_dict = {'Credits Issued': None,
                            'Credit Date': None,
                            'Certif': False
                           } 

            count += 1
            if count % intervals == 0:
                if verbose:
                    diff = datetime.now(UTC) - start
                    timeleft = diff * (total - count) / intervals
                    hours, remainder = divmod(timeleft.seconds, 3600)
                    minutes, seconds = divmod(remainder, 60)
                    sys.stdout.write("\n{count}/{total} completed ~{hours:02}:{minutes:02} remaining\n".format(count=count, total=total, hours=hours, minutes=minutes))
                    start = datetime.now(UTC)
                else:
                    sys.stdout.write('.')

            usr_profile = UserProfile.objects.get(user=student)
            cme_profiles = CmeUserProfile.objects.filter(user=student)
            registration = PaidCourseRegistration.objects.filter(user=student, status='purchased', course_id=course_id)
            registration_order = None
            cert_info = GeneratedCertificate.objects.filter(user=student, course_id=course_id)

            # Learner Profile Data
            if cme_profiles:
                cme_profile = cme_profiles[0]

            for field, label in PROFILE_FIELDS:
                fieldvalue = getattr(cme_profile, field, '') or getattr(usr_profile, field, '') or getattr(student, field, '')
                student_dict[label] = fieldvalue

            # Learner Registration Data
            if registration:
                registration = registration[0]
                registration_order = registration.order
            student_dict['Date Registered'] = getattr(registration_order, 'purchase_time', '')
            student_dict['System ID'] = '' # Untracked
            student_dict['Reference'] = '' # Untracked
            student_dict['Dietary Restrictions'] = '' # Untracked
            student_dict['Marketing Source'] = '' # Untracked
            student_dict['Fee Charged'] = getattr(registration, 'line_cost', '')
            student_dict['Amount Paid'] = getattr(registration, 'line_cost', '')
            student_dict['Payment Type'] = getattr(registration_order, 'bill_to_cardtype', '')
            student_dict['Reference Number'] = getattr(registration_order, 'bill_to_ccnum', '')
            student_dict['Paid By'] = ' '.join((getattr(registration_order, 'bill_to_first', ''), 
                                                getattr(registration_order, 'bill_to_last', '')))

            # Learner Credit Data
            if cert_info:
                cert_info = cert_info[0]
            cert_status = getattr(cert_info, 'status', '')
            student_dict['Credit Date'] = getattr(cert_info, 'created_date', '')
            student_dict['Certif'] = (cert_status == 'downloadable')
            if cert_status in ('downloadable', 'generating'):
                #XXX should be revisited when credit count functionality implemented
                student_dict['Credits Issued'] = 23.5

            for item in student_dict:
              if type(student_dict[item]) is datetime:
                student_dict[item] = student_dict[item].strftime("%m/%d/%Y")

              student_dict[item] = unicode(student_dict[item]).encode('utf-8')
              student_dict[item] = student_dict[item].replace("_"," ")

            csvwriter.writerow(student_dict)

        outfile.close()
        sys.stdout.write("Data written to {name}\n".format(name=outfile_name))
