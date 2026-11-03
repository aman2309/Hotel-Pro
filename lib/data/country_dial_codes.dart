class CountryDialCode {
  const CountryDialCode({required this.name, required this.dialCode});

  final String name;
  final String dialCode;

  String get label => '$dialCode  $name';
}

const CountryDialCode kDefaultCountryDial = CountryDialCode(
  name: 'India',
  dialCode: '+91',
);

const List<CountryDialCode> kCountryDialCodes = [
  CountryDialCode(name: 'India', dialCode: '+91'),
  CountryDialCode(name: 'United Arab Emirates', dialCode: '+971'),
  CountryDialCode(name: 'Saudi Arabia', dialCode: '+966'),
  CountryDialCode(name: 'Qatar', dialCode: '+974'),
  CountryDialCode(name: 'Kuwait', dialCode: '+965'),
  CountryDialCode(name: 'Oman', dialCode: '+968'),
  CountryDialCode(name: 'Bahrain', dialCode: '+973'),
  CountryDialCode(name: 'Nepal', dialCode: '+977'),
  CountryDialCode(name: 'Bangladesh', dialCode: '+880'),
  CountryDialCode(name: 'Sri Lanka', dialCode: '+94'),
  CountryDialCode(name: 'Pakistan', dialCode: '+92'),
  CountryDialCode(name: 'Singapore', dialCode: '+65'),
  CountryDialCode(name: 'Malaysia', dialCode: '+60'),
  CountryDialCode(name: 'Thailand', dialCode: '+66'),
  CountryDialCode(name: 'United Kingdom', dialCode: '+44'),
  CountryDialCode(name: 'United States', dialCode: '+1'),
  CountryDialCode(name: 'Canada', dialCode: '+1'),
  CountryDialCode(name: 'Australia', dialCode: '+61'),
  CountryDialCode(name: 'Germany', dialCode: '+49'),
  CountryDialCode(name: 'France', dialCode: '+33'),
];
