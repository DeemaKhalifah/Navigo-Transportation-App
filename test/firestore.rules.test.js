const fs = require('node:fs');
const path = require('node:path');
const { after, before, describe, it } = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

const projectId = 'demo-navigo';
let testEnv;

function dbAs(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function unauthDb() {
  return testEnv.unauthenticatedContext().firestore();
}

function routeDoc(db, routeId = 'routeA') {
  return db.collection('route').doc(routeId);
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
  });

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('users').doc('passengerA').set({ role: 'passenger' });
    await db.collection('users').doc('passengerB').set({ role: 'passenger' });
    await db.collection('users').doc('driverA').set({ role: 'driver' });
    await db.collection('users').doc('driverB').set({ role: 'driver' });
    await db.collection('users').doc('managerA').set({
      role: 'route_manager',
      routeId: 'routeA',
    });
    await db.collection('route_manger').doc('managerA').set({
      role: 'route_manager',
      routeId: 'routeA',
    });
    await db.collection('users').doc('adminA').set({ role: 'admin' });
    await db.collection('drivers').doc('driverA').set({
      userId: 'driverA',
      role: 'driver',
      isApproved: false,
      routeId: 'routeA',
    });
    await routeDoc(db, 'routeA').set({
      routeId: 'routeA',
      price: 5,
      driverQueueIds: ['driverA'],
      scheduleSlots: [
        {
          slotId: 'slotA',
          driverId: 'driverA',
          capacity: 1,
          passengersIds: [],
          price: 5,
          status: 'onTrip',
        },
      ],
    });
    await routeDoc(db, 'routeB').set({
      routeId: 'routeB',
      price: 7,
      driverQueueIds: [],
      scheduleSlots: [],
    });
    await db.collection('tripDriverRequests').doc('reqA').set({
      passengerId: 'passengerA',
      driverId: 'driverA',
      routeId: 'routeA',
      slotId: 'slotA',
      status: 'pending',
    });
    await db.collection('trips').doc('tripA').set({
      passengerId: 'passengerA',
      driverId: 'driverA',
      routeId: 'routeA',
      slotId: 'slotA',
      status: 'accepted',
    });
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe('Navigo Firestore security rules', () => {
  it('passenger cannot edit route price', async () => {
    await assertFails(routeDoc(dbAs('passengerA')).update({ price: 99 }));
  });

  it('passenger cannot modify embedded schedule slots directly', async () => {
    await assertFails(routeDoc(dbAs('passengerA')).update({ scheduleSlots: [] }));
  });

  it('passenger cannot modify driver queue directly', async () => {
    await assertFails(routeDoc(dbAs('passengerA')).update({ driverQueueIds: [] }));
  });

  it('passenger cannot create a notification for another user', async () => {
    await assertFails(dbAs('passengerA').collection('notifications').add({
      userId: 'driverA',
      isRead: false,
      title: 'Blocked',
      message: 'Blocked',
    }));
  });

  it('passenger cannot update another passenger profile', async () => {
    await assertFails(
      dbAs('passengerA').collection('passengers').doc('passengerB').set(
        { fullName: 'Wrong user' },
        { merge: true },
      ),
    );
  });

  it('driver cannot approve their own account', async () => {
    await assertFails(
      dbAs('driverA').collection('drivers').doc('driverA').update({
        isApproved: true,
      }),
    );
  });

  it('driver cannot modify another driver trip request', async () => {
    await assertFails(
      dbAs('driverB').collection('tripDriverRequests').doc('reqA').update({
        status: 'accepted',
      }),
    );
  });

  it('route manager can manage assigned route', async () => {
    await assertSucceeds(
      routeDoc(dbAs('managerA'), 'routeA').update({
        price: 6,
      }),
    );
  });

  it('route manager cannot manage another route', async () => {
    await assertFails(
      routeDoc(dbAs('managerA'), 'routeB').update({
        price: 8,
      }),
    );
  });

  it('admin can perform authorized management operations', async () => {
    await assertSucceeds(
      dbAs('adminA').collection('drivers').doc('driverA').update({
        isApproved: true,
      }),
    );
  });

  it('unauthenticated users cannot perform protected writes', async () => {
    await assertFails(
      unauthDb().collection('users').doc('anonymous').set({ role: 'passenger' }),
    );
    await assertFails(
      unauthDb().collection('route').doc('routeA').update({ price: 12 }),
    );
  });

  it('trusted passenger booking write is admin-only when simulated by Admin SDK', async () => {
    await assertFails(dbAs('passengerA').collection('tripDriverRequests').add({
      passengerId: 'passengerA',
      driverId: 'driverA',
      routeId: 'routeA',
      slotId: 'slotA',
      status: 'pending',
    }));
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await assertSucceeds(context.firestore().collection('tripDriverRequests').add({
        passengerId: 'passengerA',
        driverId: 'driverA',
        routeId: 'routeA',
        slotId: 'slotA',
        status: 'pending',
      }));
    });
  });

  it('overbooking by direct client schedule-slot mutation is rejected', async () => {
    await assertFails(routeDoc(dbAs('passengerA')).update({
      scheduleSlots: [
        {
          slotId: 'slotA',
          driverId: 'driverA',
          capacity: 1,
          passengersIds: ['passengerA', 'passengerB'],
          price: 5,
          status: 'onTrip',
        },
      ],
    }));
  });
});
