const {readFileSync} = require('node:fs');
const {join} = require('node:path');

const DEFAULT_ROOMS = JSON.parse(
  readFileSync(join(__dirname, '../../shared/default_rooms.json'), 'utf8'),
);

function emptyRoomDocument(spec) {
  return {
    roomNumber: spec.roomNumber,
    roomName: '',
    roomType: spec.roomType,
    normalRent: spec.normalRent,
    status: 'EMPTY',
    faultReason: '',
    mobile: '',
    guestName: '',
    idNumber: '',
    guestAddress: '',
    bookingRate: spec.normalRent,
    bookingDate: null,
    bookingTime: null,
    bookingEndTime: null,
    checkoutTime: null,
    days: 0,
    advance: 0,
    paymentMode: '',
    billNumber: '',
    applyGst: false,
    futureBooking: false,
    futureMobile: '',
    futureGuestName: '',
    futureIdNumber: '',
    futureGuestAddress: '',
    futureBookingRate: spec.normalRent,
    futureBookingDate: null,
    futureBookingEnd: null,
    futureDays: 0,
    futureAdvance: 0,
    futurePaymentMode: '',
    charges: [],
    partPayments: [],
    extraGuests: [],
    futureExtraGuests: [],
    schemaVersion: 3,
    deleted: false,
  };
}

module.exports = {DEFAULT_ROOMS, emptyRoomDocument};
