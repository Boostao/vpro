const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const { render } = require('svelte/server');
const { compile } = require('svelte/compiler');
const { loadTypeScript, serverComponent, componentFunctions, srcPath } = require('./svelteTestHelpers.cjs');
const { editor: creationEditor, picture, owner, selection, receipt, requestId } = require('./pictureCreationTestHelpers.cjs');
const { metadata, cell, transport } = require('./siviParentTestHelpers.cjs');

const reads = loadTypeScript('readRequests.ts', { '@wailsio/runtime': {} });
const { PictureCreationSession } = loadTypeScript('pictureCreationSession.ts', {
  './readRequests': reads,
  './pictureRead': picture,
  './pictureCreationEditor': creationEditor,
  './siviRequestId': loadTypeScript('siviRequestId.ts'),
});
const pictureReadMod = loadTypeScript('pictureRead.ts', {
  './projectMetadataEditor': metadata,
  './siviParentTransport': transport,
});
const metadataEditorMod = loadTypeScript('pictureMetadataEditor.ts', {
  '../../resources/picture-metadata-policy.json': require('../../resources/picture-metadata-policy.json'),
  './projectMetadataEditor': metadata,
  './pictureRead': pictureReadMod,
});
const metadataSessionMod = loadTypeScript('pictureMetadataSession.ts', {
  './readRequests': reads,
  './projectMetadataEditor': metadata,
  './pictureRead': pictureReadMod,
  './pictureMetadataEditor': metadataEditorMod,
});

const iconsProxy = new Proxy({}, { get: () => () => {} });
const operation = (val) => Object.assign(Promise.resolve(val), { cancel() {} });

test('UX-SPATIAL-006: failed or cancelled native chooser never locks PictureCreationSession or PictureManager', async () => {
  // 1. Server-mode / native chooser failure leaves session idle, unblocked, and retryable
  let attempt = 0;
  const session = new PictureCreationSession(owner, {
    choose: () => {
      attempt++;
      if (attempt === 1) {
        return operation(Promise.reject(new Error('RuntimeError: picture selection requires its live native request window')));
      }
      if (attempt === 2) {
        return operation(null); // user cancel
      }
      return operation(selection());
    },
    recoverSelection: () => operation(Promise.reject(new Error('RuntimeError: picture selection requires its live native request window'))),
    create: (_token, json) => operation(receipt(JSON.parse(json))),
    receipt: () => operation(null),
    image: () => operation(null),
    release: () => operation(),
    acknowledge: () => operation(),
  });

  // Attempt 1: chooser rejects -> unblocked immediately
  assert.equal(await session.add(requestId), false);
  assert.equal(session.view().phase, 'idle');
  assert.equal(session.view().busy, false);
  assert.equal(session.view().blocked, false);
  assert.equal(session.view().selection, null);
  assert.equal(session.view().request, null);
  assert.deepEqual(JSON.parse(JSON.stringify(session.closeState())), {
    unsaved: false,
    busy: false,
    blocked: false,
    canSave: false,
    saveReason: '',
    error: session.view().error,
  });
  assert.match(session.view().error, /live native request window/);

  // Even if release() is invoked on an unattempted idle state, it succeeds cleanly without throwing
  assert.equal(await session.release(), true);
  assert.equal(session.closeState().blocked, false);

  // Attempt 2: user cancels native chooser -> stays unblocked
  const secondId = requestId.replace('0001', '0002');
  assert.equal(await session.add(secondId), false);
  assert.equal(session.closeState().blocked, false);
  assert.equal(session.view().error, null);

  // Attempt 3: chooser succeeds on retry -> commits and acknowledges cleanly
  const thirdId = requestId.replace('0001', '0003');
  assert.equal(await session.add(thirdId), true);
  assert.equal(session.closeState().blocked, true);
  assert.equal(await session.acknowledge(), true);
  assert.equal(session.closeState().blocked, false);

  // 2. PictureManager plot switching remains enabled when creationBlocked is false after chooser failure
  const busyStates = [];
  const mgr = componentFunctions('PictureManager.svelte', ['selectPlot', 'reading'], {
    busy: false,
    metadataBlocked: false,
    creationBlocked: session.closeState().blocked || session.closeState().busy || session.closeState().unsaved,
    lifecycleBlocked: false,
    selected: '108050',
    plot: '00337',
    project: 'Sample',
    error: '',
    plotLookupInputError: () => null,
    onBusyChange: (val) => busyStates.push(val),
  });
  mgr.actions.reading(false);
  mgr.actions.selectPlot();
  assert.deepEqual(busyStates, [false]);
  assert.equal(mgr.selected, '00337');
  assert.equal(mgr.error, '');
});

test('UX-SPATIAL-007: PicComment supports NULL -> text -> text -> NULL / empty saves and SSR input readiness', async () => {
  let storedRow = {
    rowId: '1',
    cells: [
      cell('integer', '1'),
      cell('text', 'Default'),
      cell('text', 'Pic01.jpg'),
      cell('text', '108050'),
      cell(), // NULL PicComment
    ],
  };
  const columns = ['ID', 'PicDir', 'PicName', 'PlotNumber', 'PicComment'].map((name) => ({ name, declaredType: 'TEXT' }));
  const picOwner = { contextId: 'ctx-1', project: 'Sample', plotNumber: '108050' };
  const savedChanges = [];

  const metaSession = new metadataSessionMod.PictureMetadataSession(picOwner, {
    read: () => operation({ ...picOwner, records: { columns, rows: [structuredClone(storedRow)] } }),
    save: (json) => {
      const req = JSON.parse(json);
      savedChanges.push(req.changes);
      const next = structuredClone(req.original);
      for (const ch of req.changes) {
        const idx = req.columns.findIndex((c) => c.name === ch.column);
        next.cells[idx] = structuredClone(ch.value);
      }
      storedRow = next;
      return operation({
        ...req,
        ...picOwner,
        requestedSource: '/data/pics/VPics.db',
        source: '/data/pics/VPics.db',
        ownedFiles: { 'attachment:project': '/data/projects/Sample.db' },
        actor: 'Admin',
        auditStrength: 3,
        committed: structuredClone(next),
        editWhen: '2026-11-19T12:00:00Z',
        historyId: String(savedChanges.length),
        didCommit: true,
        replayed: false,
      });
    },
    receipt: () => operation(null),
  });

  metaSession.select({ ...picOwner, records: { columns, rows: [structuredClone(storedRow)] } }, '1');

  // Verify SSR renders #picture-metadata-PicComment enabled even when PicComment is initially NULL
  const EditorSSR = serverComponent(readFileSync(srcPath('PictureMetadataEditor.svelte'), 'utf8'), 'PictureMetadataEditor.svelte', {
    './pictureMetadataEditor': metadataEditorMod,
  });
  const html = render(EditorSSR, { props: { session: metaSession, disabled: false } }).body;
  const commentInputMatch = html.match(/<input[^>]*id="picture-metadata-PicComment"[^>]*>/);
  assert.ok(commentInputMatch, 'Expected #picture-metadata-PicComment input');
  assert.equal(/\bdisabled(?:\s|=|>)/.test(commentInputMatch[0]), false, 'PicComment input must be typeable directly when NULL');

  // 1. NULL -> text
  metaSession.stage('PicComment', 'Canopy gap facing south', false);
  assert.equal(metaSession.closeState().unsaved, true);
  assert.equal(metaSession.closeState().canSave, true);
  assert.equal(await metaSession.save('00000000-0000-4000-8000-000000000011'), true);
  assert.equal(storedRow.cells[4].storage, 'text');
  assert.equal(storedRow.cells[4].text, 'Canopy gap facing south');

  // 2. text -> text
  metaSession.stage('PicComment', 'Updated subalpine fir stand', false);
  assert.equal(await metaSession.save('00000000-0000-4000-8000-000000000012'), true);
  assert.equal(storedRow.cells[4].storage, 'text');
  assert.equal(storedRow.cells[4].text, 'Updated subalpine fir stand');

  // 3. text -> empty input clears to NULL
  metaSession.stage('PicComment', '', false);
  assert.equal(metaSession.closeState().unsaved, true);
  assert.equal(metaSession.closeState().canSave, true);
  assert.equal(await metaSession.save('00000000-0000-4000-8000-000000000013'), true);
  assert.equal(storedRow.cells[4].storage, 'null');
  assert.equal(storedRow.cells[4].text, null);

  // 4. NULL -> text -> explicit NULL checkbox
  metaSession.stage('PicComment', 'Temporary note', false);
  assert.equal(await metaSession.save('00000000-0000-4000-8000-000000000014'), true);
  metaSession.stage('PicComment', 'Temporary note', true);
  assert.equal(await metaSession.save('00000000-0000-4000-8000-000000000015'), true);
  assert.equal(storedRow.cells[4].storage, 'null');
});

test('UX-SPATIAL-007: PictureOptions library and folder paths validate, persist, and render in UserSetupModal and PictureManager', async () => {
  let persistedOptions = {
    pictureLibraryPath: '',
    childDirectory: '',
    managerDirectory: '',
    effectiveLibraryPath: '/data/pics/VPics.db',
    effectiveChildDirectory: '/data/pics/images',
    effectiveManagerDirectory: '/data/pics/images',
    defaultLibraryPath: '/data/pics/VPics.db',
    defaultImagesDirectory: '/data/pics/images',
    envOverride: false,
  };
  const optionCalls = [];

  const userSetup = loadTypeScript('shell/userSetupModal.ts', {
    '../../bindings/github.com/boostao/vpro/app': {
      ContextService: {
        GetUserSetup: async () => ({
          userName: 'Admin',
          accredited: false,
          masterBecAllowed: false,
          inUserRestrictions: false,
          canEditBecSiteUnit: false,
        }),
        SetUserName: async (_ctx, user) => ({
          userName: user,
          accredited: false,
          masterBecAllowed: false,
          inUserRestrictions: false,
          canEditBecSiteUnit: false,
        }),
      },
      PlotEntryService: {},
      PictureService: {
        GetPictureOptions: async () => {
          optionCalls.push(['get']);
          return structuredClone(persistedOptions);
        },
        SavePictureOptions: async (update) => {
          optionCalls.push(['save', structuredClone(update)]);
          persistedOptions = {
            ...persistedOptions,
            pictureLibraryPath: update.pictureLibraryPath,
            childDirectory: update.childDirectory,
            managerDirectory: update.managerDirectory,
            effectiveLibraryPath: update.pictureLibraryPath || persistedOptions.defaultLibraryPath,
            effectiveChildDirectory: update.childDirectory || persistedOptions.defaultImagesDirectory,
            effectiveManagerDirectory: update.managerDirectory || persistedOptions.defaultImagesDirectory,
          };
          return structuredClone(persistedOptions);
        },
      },
    },
  });

  // Validate relative vs absolute / blank paths
  assert.equal(
    userSetup.validatePictureOptionsInput({
      pictureLibraryPath: 'relative/VPics.db',
      childDirectory: '',
      managerDirectory: '',
    }).valid,
    false,
  );
  assert.deepEqual(
    JSON.parse(
      JSON.stringify(
        userSetup.validatePictureOptionsInput({
          pictureLibraryPath: '  /mnt/photos/VPics.db  ',
          childDirectory: '  C:\\Photos\\Child  ',
          managerDirectory: '',
        }),
      ),
    ),
    {
      valid: true,
      value: {
        pictureLibraryPath: '/mnt/photos/VPics.db',
        childDirectory: 'C:\\Photos\\Child',
        managerDirectory: '',
      },
      error: '',
    },
  );

  // Exercise port round-trip: get -> custom save -> reset defaults
  const loaded = await userSetup.defaultUserSetupPort.getPictureOptions();
  assert.equal(loaded.effectiveLibraryPath, '/data/pics/VPics.db');

  const updated = await userSetup.defaultUserSetupPort.savePictureOptions({
    pictureLibraryPath: '/custom/VPics.db',
    childDirectory: '/custom/child',
    managerDirectory: '/custom/manager',
  });
  assert.equal(updated.effectiveLibraryPath, '/custom/VPics.db');
  assert.equal(updated.effectiveManagerDirectory, '/custom/manager');

  const reset = await userSetup.defaultUserSetupPort.savePictureOptions({
    pictureLibraryPath: '',
    childDirectory: '',
    managerDirectory: '',
  });
  assert.equal(reset.effectiveLibraryPath, '/data/pics/VPics.db');
  assert.equal(optionCalls.length, 3);

  // Verify UserSetupModal compiles cleanly and renders PictureOptions controls
  const modalSrc = readFileSync(srcPath('shell/UserSetupModal.svelte'), 'utf8');
  assert.deepEqual(compile(modalSrc, { filename: 'UserSetupModal.svelte', generate: 'client' }).warnings, []);
  const ModalSSR = serverComponent(modalSrc, 'UserSetupModal.svelte', {
    '@lucide/svelte': iconsProxy,
    './userSetupModal': userSetup,
  });
  const modalHtml = render(ModalSSR, {
    props: { open: true, contextId: 'ctx-1', activeProject: 'Sample', onclose: () => {} },
  }).body;
  assert.match(modalHtml, /data-user-picture-options-panel/);
  assert.match(modalHtml, /data-picture-library-path-input/);
  assert.match(modalHtml, /data-picture-child-dir-input/);
  assert.match(modalHtml, /data-picture-manager-dir-input/);
  assert.match(modalHtml, /data-picture-options-save/);
  assert.match(modalHtml, /data-picture-options-reset/);

  // Verify UserSetupModal savePicturePaths action updates state and rejects relative paths
  const modalCtx = componentFunctions('shell/UserSetupModal.svelte', ['applyPictureOptions', 'savePicturePaths'], {
    saving: false,
    pictureSaving: false,
    loading: false,
    loadGen: 0,
    error: '',
    savedNotice: '',
    pictureOptions: null,
    draftLibraryPath: 'relative/path.db',
    draftChildDir: '',
    draftManagerDir: '',
    port: userSetup.defaultUserSetupPort,
    validatePictureOptionsInput: userSetup.validatePictureOptionsInput,
  });
  await modalCtx.actions.savePicturePaths(false);
  assert.match(modalCtx.error, /full absolute path/);

  modalCtx.draftLibraryPath = '/srv/bec/VPics.db';
  modalCtx.draftManagerDir = '/srv/bec/photos';
  await modalCtx.actions.savePicturePaths(false);
  assert.equal(modalCtx.error, '');
  assert.match(modalCtx.savedNotice, /Saved picture library/);
  assert.equal(modalCtx.pictureOptions.effectiveLibraryPath, '/srv/bec/VPics.db');

  await modalCtx.actions.savePicturePaths(true);
  assert.equal(modalCtx.draftLibraryPath, '');
  assert.equal(modalCtx.pictureOptions.effectiveLibraryPath, '/data/pics/VPics.db');
});
